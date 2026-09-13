// Company marks operations action.
// Called by the product team (populate, refresh, status) and by the daily retention job
// (purge) with a shared job secret. Fetches each approved company's own published icon,
// stores it versioned in the public company-marks bucket, and records every outcome through
// service-role RPCs. Long runs continue themselves in batches so one operator command covers
// the whole registry. No member data is involved anywhere in this function.
import { jsonResponse, requiredEnvironment, secretsMatch } from "../_shared/http.ts";
import {
  candidateIconURLs,
  chooseMark,
  companyKeyPattern,
  contentTypeFor,
  type DecodedCandidate,
  extractICOEntries,
  type FetchFailureReason,
  inspectImage,
  isSafeIconURL,
  manifestURL,
  maxMarkBytes,
  objectPath,
  parseManifestIcons,
} from "../_shared/company_marks.ts";

const batchSize = 10;
const maxInvocations = 60;
const requestTimeoutMs = 8_000;
const companyBudgetMs = 30_000;
const maxDownloadsPerCompany = 6;
const htmlLimit = 512 * 1024;
const manifestLimit = 64 * 1024;

interface RunTarget {
  key: string;
  name: string;
  website_url: string | null;
  domains: string[];
  mark_version: number;
  refresh: boolean;
}

interface RequestBody {
  action?: string;
  companies?: unknown;
  requested_by?: unknown;
  run_id?: unknown;
  invocation?: unknown;
}

type ItemOutcome = "fetched" | "no_icon_published" | "fetch_failed";

class DownloadError extends Error {
  reason: FetchFailureReason;
  constructor(reason: FetchFailureReason, message: string) {
    super(message);
    this.reason = reason;
  }
}

function serviceHeaders(extra: Record<string, string> = {}): Record<string, string> {
  const key = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  return { apikey: key, authorization: `Bearer ${key}`, ...extra };
}

async function rpc<T>(name: string, body: unknown): Promise<T> {
  const url = requiredEnvironment("SUPABASE_URL");
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: serviceHeaders({ "content-type": "application/json" }),
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    throw new Error(`${name} failed with ${response.status}: ${detail.slice(0, 200)}`);
  }
  if (response.status === 204) return undefined as T;
  return await response.json() as T;
}

/** Downloads at most `limit` bytes from a public host; anything longer is too_large. */
async function download(url: string, limit: number): Promise<{ bytes: Uint8Array; finalURL: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), requestTimeoutMs);
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      redirect: "follow",
      headers: { "user-agent": "network.to company-marks/1.0", accept: "*/*" },
    });
    const finalURL = response.url || url;
    if (!isSafeIconURL(finalURL)) {
      await response.body?.cancel();
      throw new DownloadError("unreachable", "redirected to an unsafe address");
    }
    if (!response.ok) {
      await response.body?.cancel();
      throw new DownloadError("unreachable", `status ${response.status}`);
    }
    const declared = Number(response.headers.get("content-length") ?? "0");
    if (declared > limit) {
      await response.body?.cancel();
      throw new DownloadError("too_large", `content-length ${declared}`);
    }
    const reader = response.body?.getReader();
    if (!reader) throw new DownloadError("unreachable", "empty body");
    const chunks: Uint8Array[] = [];
    let total = 0;
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > limit) {
        await reader.cancel();
        throw new DownloadError("too_large", `body exceeds ${limit} bytes`);
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return { bytes, finalURL };
  } catch (error) {
    if (error instanceof DownloadError) throw error;
    throw new DownloadError("unreachable", error instanceof Error ? error.message : "network error");
  } finally {
    clearTimeout(timer);
  }
}

interface Discovery {
  outcome: ItemOutcome;
  reason?: string;
  candidate?: DecodedCandidate;
  kind?: "png" | "jpeg";
}

async function discoverMark(target: RunTarget): Promise<Discovery> {
  const startedAt = Date.now();
  const website = target.website_url ?? (target.domains[0] ? `https://${target.domains[0]}` : null);
  if (!website || !isSafeIconURL(website)) return { outcome: "fetch_failed", reason: "unreachable" };

  const failures: FetchFailureReason[] = [];
  let html = "";
  let baseURL = website;
  try {
    const page = await download(website, htmlLimit);
    html = new TextDecoder("utf-8", { fatal: false }).decode(page.bytes);
    baseURL = page.finalURL;
  } catch (error) {
    failures.push(error instanceof DownloadError ? error.reason : "unreachable");
  }

  let manifestIcons: ReturnType<typeof parseManifestIcons> = [];
  const manifest = html ? manifestURL(html, baseURL) : null;
  if (manifest && Date.now() - startedAt < companyBudgetMs) {
    try {
      const file = await download(manifest, manifestLimit);
      manifestIcons = parseManifestIcons(new TextDecoder().decode(file.bytes), file.finalURL);
    } catch {
      // A missing manifest only removes candidates.
    }
  }

  const decoded: DecodedCandidate[] = [];
  let downloads = 0;
  for (const candidate of candidateIconURLs(html, baseURL, manifestIcons)) {
    if (downloads >= maxDownloadsPerCompany || Date.now() - startedAt > companyBudgetMs) break;
    downloads += 1;
    try {
      const file = await download(candidate.url, maxMarkBytes);
      const info = inspectImage(file.bytes);
      if (!info) {
        failures.push("wrong_kind");
        continue;
      }
      if (info.kind === "ico") {
        for (const entry of extractICOEntries(file.bytes)) {
          const entryInfo = inspectImage(entry);
          if (entryInfo) decoded.push({ url: file.finalURL, bytes: entry, info: entryInfo });
        }
        continue;
      }
      decoded.push({ url: file.finalURL, bytes: file.bytes, info });
      const side = Math.min(info.width, info.height);
      if (side >= 512 && Math.abs(info.width - info.height) <= side * 0.1) break;
    } catch (error) {
      failures.push(error instanceof DownloadError ? error.reason : "unreachable");
    }
  }

  const choice = chooseMark(decoded, failures);
  if (choice.outcome === "fetched") {
    return { outcome: "fetched", candidate: choice.candidate, kind: choice.candidate.info.kind === "jpeg" ? "jpeg" : "png" };
  }
  return { outcome: choice.outcome, reason: choice.reason };
}

async function uploadMark(path: string, bytes: Uint8Array, contentType: string): Promise<boolean> {
  const url = requiredEnvironment("SUPABASE_URL");
  const response = await fetch(`${url}/storage/v1/object/company-marks/${path}`, {
    method: "POST",
    headers: serviceHeaders({ "content-type": contentType, "x-upsert": "true", "cache-control": "31536000" }),
    body: new Uint8Array(bytes).buffer,
  });
  if (!response.ok) console.error("company_mark_upload_failed", path, response.status);
  await response.body?.cancel();
  return response.ok;
}

async function deleteMark(path: string): Promise<boolean> {
  const url = requiredEnvironment("SUPABASE_URL");
  const response = await fetch(`${url}/storage/v1/object/company-marks/${path}`, {
    method: "DELETE",
    headers: serviceHeaders(),
  });
  await response.body?.cancel();
  return response.ok || response.status === 404;
}

async function recordOutcome(runID: string, key: string, outcome: ItemOutcome, reason: string): Promise<void> {
  await rpc("record_company_mark_outcome", {
    p_run_id: runID,
    p_company_key: key,
    p_outcome: outcome,
    p_failure_reason: reason,
  });
}

async function processCompany(runID: string, target: RunTarget): Promise<void> {
  const discovered = await discoverMark(target);
  if (discovered.outcome !== "fetched" || !discovered.candidate || !discovered.kind) {
    await recordOutcome(runID, target.key, discovered.outcome, discovered.reason ?? discovered.outcome);
    console.log(discovered.outcome === "no_icon_published" ? "company_mark_no_icon" : "company_mark_fetch_failed", target.key, discovered.reason ?? "");
    return;
  }

  const path = objectPath(target.key, target.mark_version + 1, discovered.kind);
  const contentType = contentTypeFor(discovered.kind);
  if (!(await uploadMark(path, discovered.candidate.bytes, contentType))) {
    await recordOutcome(runID, target.key, "fetch_failed", "upload_failed");
    console.error("company_mark_fetch_failed", target.key, "upload_failed");
    return;
  }
  await rpc("record_company_mark_outcome", {
    p_run_id: runID,
    p_company_key: target.key,
    p_outcome: "fetched",
    p_path: path,
    p_content_type: contentType,
    p_byte_size: discovered.candidate.bytes.byteLength,
    p_width: discovered.candidate.info.width,
    p_height: discovered.candidate.info.height,
    p_source_url: discovered.candidate.url.slice(0, 500),
  });
  console.log("company_mark_fetched", target.key, target.mark_version + 1);
}

async function purgeDueFiles(): Promise<{ purged: number; failed: number }> {
  const due = await rpc<Array<{ key: string; version: number; path: string }>>("list_company_mark_purges", { p_limit: 50 });
  let purged = 0;
  let failed = 0;
  for (const version of due ?? []) {
    if (!(await deleteMark(version.path))) {
      failed += 1;
      console.error("company_mark_purge_failed", version.key, version.version);
      continue;
    }
    await rpc("confirm_company_mark_purge", { p_company_key: version.key, p_version: version.version });
    purged += 1;
  }
  return { purged, failed };
}

function selfURL(): string {
  return `${requiredEnvironment("SUPABASE_URL")}/functions/v1/company-marks`;
}

async function continueRun(action: string, runID: string, invocation: number, secret: string, purged: number): Promise<void> {
  try {
    const response = await fetch(selfURL(), {
      method: "POST",
      headers: { "content-type": "application/json", "x-job-secret": secret },
      body: JSON.stringify({ action, run_id: runID, invocation, purged }),
    });
    await response.body?.cancel();
    if (!response.ok) {
      console.error("company_mark_run_continuation_failed", runID, response.status);
      await rpc("finish_company_mark_run", { p_run_id: runID, p_status: "failed", p_error: `continuation returned ${response.status}` });
    }
  } catch (error) {
    console.error("company_mark_run_continuation_failed", runID, error instanceof Error ? error.message : error);
    await rpc("finish_company_mark_run", { p_run_id: runID, p_status: "failed", p_error: "continuation request failed" }).catch(() => {});
  }
}

async function processBatch(action: string, runID: string, invocation: number, secret: string, purgedSoFar: number): Promise<void> {
  try {
    let purged = purgedSoFar;
    if (invocation === 1) purged += (await purgeDueFiles()).purged;
    const targets = await rpc<RunTarget[]>("claim_company_mark_targets", { p_run_id: runID, p_limit: batchSize });
    for (const target of targets ?? []) {
      try {
        await processCompany(runID, target);
      } catch (error) {
        console.error("company_mark_fetch_failed", target.key, error instanceof Error ? error.message : error);
        await recordOutcome(runID, target.key, "fetch_failed", "unexpected error").catch(() => {});
      }
    }
    if ((targets?.length ?? 0) >= batchSize && invocation < maxInvocations) {
      await continueRun(action, runID, invocation + 1, secret, purged);
      return;
    }
    await rpc("finish_company_mark_run", { p_run_id: runID, p_status: "completed", p_summary: { purged, invocations: invocation } });
    console.log("company_mark_run_completed", runID, invocation);
  } catch (error) {
    console.error("company_mark_run_failed", runID, error instanceof Error ? error.message : error);
    await rpc("finish_company_mark_run", {
      p_run_id: runID,
      p_status: "failed",
      p_error: error instanceof Error ? error.message : "Unexpected error",
    }).catch(() => {});
  }
}

/** Continues after the response is sent when the runtime supports it. */
function runInBackground(work: Promise<void>): void {
  const runtime = (globalThis as { EdgeRuntime?: { waitUntil?: (promise: Promise<unknown>) => void } }).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(work);
  } else {
    work.catch((error) => console.error("company_mark_background_failed", error instanceof Error ? error.message : error));
  }
}

function parseCompanies(value: unknown): string[] | null {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value) || value.length > 300) throw new Error("Invalid company list");
  const keys = value.map((entry) => String(entry));
  if (keys.some((key) => !companyKeyPattern.test(key))) throw new Error("Invalid company key");
  return keys;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  const expectedSecret = Deno.env.get("COMPANY_MARKS_JOB_SECRET") ?? "";
  const presentedSecret = request.headers.get("x-job-secret") ?? "";
  if (!(await secretsMatch(presentedSecret, expectedSecret))) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let body: RequestBody & { purged?: unknown } = {};
  try {
    const text = await request.text();
    body = text ? JSON.parse(text) as RequestBody : {};
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  const action = typeof body.action === "string" ? body.action : "populate";

  try {
    if (action === "status") {
      return jsonResponse({ companies: await rpc<unknown[]>("get_company_mark_overview", {}) });
    }
    if (action === "purge") {
      return jsonResponse(await purgeDueFiles());
    }
    if (action !== "populate" && action !== "refresh") {
      return jsonResponse({ error: "Unknown action" }, 400);
    }

    if (typeof body.run_id === "string" && body.run_id) {
      const invocation = typeof body.invocation === "number" && body.invocation >= 1 ? Math.floor(body.invocation) : 1;
      const purged = typeof body.purged === "number" && body.purged >= 0 ? Math.floor(body.purged) : 0;
      runInBackground(processBatch(action, body.run_id, invocation, presentedSecret, purged));
      return jsonResponse({ status: "running", run_id: body.run_id, invocation }, 202);
    }

    const companies = parseCompanies(body.companies);
    const scope: Record<string, unknown> = { action };
    if (companies) scope.companies = companies;
    const started = await rpc<{ status: string; run_id: string; reason?: string }>("start_company_mark_run", {
      p_scope: scope,
      p_requested_by: typeof body.requested_by === "string" ? body.requested_by.slice(0, 120) : null,
    });
    if (started.status !== "running") {
      console.log("company_mark_run_skipped", started.run_id);
      return jsonResponse(started);
    }
    console.log("company_mark_run_started", started.run_id, action);
    runInBackground(processBatch(action, started.run_id, 1, presentedSecret, 0));
    return jsonResponse({ status: "running", run_id: started.run_id, invocation: 1 }, 202);
  } catch (error) {
    if (error instanceof Response) return error;
    const message = error instanceof Error ? error.message : "Unexpected error";
    console.error("company_marks_request_failed", message);
    return jsonResponse({ error: message }, message.startsWith("Invalid") ? 400 : 500);
  }
});

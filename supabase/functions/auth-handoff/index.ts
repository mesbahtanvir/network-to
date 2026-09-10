import { requiredEnvironment } from "../_shared/http.ts";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "apikey, authorization, content-type, x-client-info",
  "access-control-allow-methods": "GET, POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "cache-control": "no-store",
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function serviceHeaders(): Record<string, string> {
  const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  return {
    apikey: serviceRoleKey,
    authorization: `Bearer ${serviceRoleKey}`,
    "content-type": "application/json",
  };
}

async function rpc(name: string, body: unknown): Promise<Response> {
  const url = requiredEnvironment("SUPABASE_URL");
  return await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: serviceHeaders(),
    body: JSON.stringify(body),
  });
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function clientAddress(request: Request): string | null {
  const direct = request.headers.get("x-real-ip") ?? request.headers.get("cf-connecting-ip");
  if (direct?.trim()) return direct.trim();
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || null;
}

async function enforceRateLimit(request: Request, action: string): Promise<Response | null> {
  const address = clientAddress(request);
  if (!address) return json({ error: "Request origin unavailable" }, 503);
  const salt = requiredEnvironment("HANDOFF_RATE_LIMIT_SALT");
  const limits: Record<string, number> = { create: 10, complete: 30, claim: 400 };
  const response = await rpc("consume_edge_rate_limit", {
    p_key_hash: await sha256(`${salt}:${address}`),
    p_action: action,
    p_limit: limits[action],
    p_window_seconds: 600,
  });
  if (!response.ok) return json({ error: "Sign-in protection unavailable" }, 503);
  if (await response.json()) return null;
  const limited = json({ error: "Too many sign-in attempts. Try again shortly." }, 429);
  limited.headers.set("retry-after", "60");
  return limited;
}

type BrowserStatus = "verified" | "expired" | "invalid" | "unavailable";

const browserMessages: Record<BrowserStatus, string> = {
  verified: "Work email verified\n\nReturn to network.to on your iPhone. You can close this tab.",
  expired: "This verification link has expired or was already used.\n\nReturn to network.to on your iPhone and request a new link.",
  invalid: "We couldn’t verify this link.\n\nReturn to network.to on your iPhone and request a new link.",
  unavailable: "Verification is temporarily unavailable.\n\nReturn to network.to on your iPhone and try again shortly.",
};

function browserResponse(status: BrowserStatus): Response {
  return new Response(browserMessages[status], {
    status: status === "verified" ? 200 : 400,
    headers: {
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; sandbox",
      "content-type": "text/plain; charset=utf-8",
      "referrer-policy": "no-referrer",
      "permissions-policy": "camera=(), microphone=(), geolocation=()",
      "x-content-type-options": "nosniff",
    },
  });
}

function browserRedirect(status: BrowserStatus): Response {
  const cleanURL = new URL("/functions/v1/auth-handoff", requiredEnvironment("SUPABASE_URL"));
  cleanURL.searchParams.set("status", status);
  return new Response(null, {
    status: 303,
    headers: {
      "cache-control": "no-store",
      location: cleanURL.toString(),
      "referrer-policy": "no-referrer",
    },
  });
}

function validRequestID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

async function completeBrowserHandoff(request: Request): Promise<Response> {
  const requestURL = new URL(request.url);
  const status = requestURL.searchParams.get("status");
  if (status && status in browserMessages) return browserResponse(status as BrowserStatus);

  const requestId = requestURL.searchParams.get("request_id") ?? "";
  const authCode = requestURL.searchParams.get("code") ?? "";
  const authError = requestURL.searchParams.has("error") || requestURL.searchParams.has("error_code");
  if (authError || !validRequestID(requestId) || authCode.length < 16 || authCode.length > 2048) {
    return browserRedirect("invalid");
  }

  try {
    const rateLimited = await enforceRateLimit(request, "complete");
    if (rateLimited) return browserRedirect("unavailable");

    const response = await rpc("complete_auth_handoff", { p_id: requestId, p_auth_code: authCode });
    if (!response.ok) return browserRedirect("unavailable");
    return browserRedirect(await response.json() ? "verified" : "expired");
  } catch {
    return browserRedirect("unavailable");
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  if (request.method === "GET") return await completeBrowserHandoff(request);
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > 4096) return json({ error: "Request too large" }, 413);

  try {
    const body = await request.json();
    const action = String(body.action ?? "");
    const requestId = String(body.request_id ?? "");
    if (!validRequestID(requestId)) return json({ error: "Invalid request" }, 400);
    if (!(action in { create: true, complete: true, claim: true })) {
      return json({ error: "Unknown action" }, 400);
    }
    const rateLimited = await enforceRateLimit(request, action);
    if (rateLimited) return rateLimited;

    if (action === "create") {
      const claimSecretHash = String(body.claim_secret_hash ?? "").toLowerCase();
      if (!/^[0-9a-f]{64}$/.test(claimSecretHash)) return json({ error: "Invalid request" }, 400);
      const response = await rpc("create_auth_handoff", {
        p_id: requestId,
        p_claim_secret_hash: claimSecretHash,
      });
      return response.ok ? json({ status: "waiting" }, 201) : json({ error: "Could not create handoff" }, 500);
    }

    if (action === "complete") {
      const authCode = String(body.auth_code ?? "");
      const response = await rpc("complete_auth_handoff", { p_id: requestId, p_auth_code: authCode });
      const completed = response.ok && await response.json();
      return completed ? json({ status: "ready" }) : json({ error: "Handoff expired" }, 410);
    }

    if (action === "claim") {
      const claimSecret = String(body.claim_secret ?? "");
      if (claimSecret.length < 32 || claimSecret.length > 128) return json({ error: "Invalid claim" }, 400);
      const response = await rpc("claim_auth_handoff", {
        p_id: requestId,
        p_claim_secret_hash: await sha256(claimSecret),
      });
      if (!response.ok) return json({ error: "Could not claim handoff" }, 500);
      const authCode = await response.json();
      return authCode ? json({ status: "ready", auth_code: authCode }) : json({ status: "waiting" }, 202);
    }

    return json({ error: "Unknown action" }, 400);
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

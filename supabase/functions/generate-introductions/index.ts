// Optional operations action: runs the daily matching batch on demand with the shared
// MATCHING_JOB_SECRET. The database owns every rule; this function only asks for a run and
// reports its record. Not deployed by default: the scheduled batch is the production path.
import { jsonResponse, requiredEnvironment, secretsMatch } from "../_shared/http.ts";

Deno.serve(async (request) => {
  try {
    if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

    const expectedSecret = requiredEnvironment("MATCHING_JOB_SECRET");
    const presentedSecret = request.headers.get("x-job-secret") ?? "";
    if (!(await secretsMatch(presentedSecret, expectedSecret))) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const url = requiredEnvironment("SUPABASE_URL");
    const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
    const response = await fetch(`${url}/rest/v1/rpc/run_matching_now`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: "{}",
    });

    if (!response.ok) {
      return jsonResponse({ error: "Matching run failed", detail: await response.text() }, 500);
    }
    const run = await response.json();
    console.log(JSON.stringify({ event: "matching_run_requested", run_id: run?.run_id, status: run?.status }));
    return jsonResponse({
      run_id: run?.run_id ?? null,
      status: run?.status ?? null,
      introductions_created: run?.introductions_created ?? 0,
    });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

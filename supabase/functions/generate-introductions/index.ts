import { jsonResponse, requiredEnvironment } from "../_shared/http.ts";

Deno.serve(async (request) => {
  try {
    const expectedSecret = requiredEnvironment("MATCHING_JOB_SECRET");
    if (request.headers.get("x-job-secret") !== expectedSecret) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const url = requiredEnvironment("SUPABASE_URL");
    const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
    const response = await fetch(`${url}/rest/v1/rpc/generate_next_introduction`, {
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
    const introductionId = await response.json();
    return jsonResponse({ introduction_id: introductionId });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});


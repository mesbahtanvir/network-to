import { authenticatedUser, jsonResponse, requiredEnvironment } from "../_shared/http.ts";

Deno.serve(async (request) => {
  if (request.method !== "DELETE") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const user = await authenticatedUser(request);
    const url = requiredEnvironment("SUPABASE_URL");
    const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");

    const adminHeaders = {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
    };
    const resumeResponse = await fetch(
      `${url}/rest/v1/resume_documents?user_id=eq.${encodeURIComponent(user.id)}&select=storage_path`,
      { headers: adminHeaders },
    );
    if (!resumeResponse.ok) {
      return jsonResponse({ error: "Could not enumerate private files before deletion" }, 500);
    }
    const resumes: Array<{ storage_path: string }> = await resumeResponse.json();
    for (const resume of resumes) {
      const objectPath = resume.storage_path.split("/").map(encodeURIComponent).join("/");
      const storageResponse = await fetch(`${url}/storage/v1/object/resumes/${objectPath}`, {
        method: "DELETE",
        headers: adminHeaders,
      });
      if (!storageResponse.ok && storageResponse.status !== 404) {
        return jsonResponse({ error: "Could not delete a private file; account deletion was stopped" }, 500);
      }
    }

    const response = await fetch(`${url}/auth/v1/admin/users/${user.id}`, {
      method: "DELETE",
      headers: adminHeaders,
    });
    if (!response.ok) {
      return jsonResponse({ error: "Account deletion failed", detail: await response.text() }, 500);
    }
    return new Response(null, { status: 204 });
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

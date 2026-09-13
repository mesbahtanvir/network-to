import { requiredEnvironment } from "./http.ts";

export type IncidentKind =
  | "account_deletion_failed"
  | "notification_delivery_failed"
  | "app_store_notification_failed"
  | "edge_function_error";

/**
 * Records an operational incident so the database alerting job can surface it.
 * Details must stay technical: never include email addresses or member-authored text.
 * Failures to record are logged and swallowed so the caller's own error handling wins.
 */
export async function recordOperationalIncident(kind: IncidentKind, detail: string, reference?: string): Promise<void> {
  try {
    const url = requiredEnvironment("SUPABASE_URL");
    const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
    const response = await fetch(`${url}/rest/v1/rpc/record_operational_incident`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ p_kind: kind, p_detail: detail.slice(0, 2000), p_reference: reference ?? null }),
    });
    if (!response.ok) console.error("operational_incident_not_recorded", kind, response.status);
  } catch (error) {
    console.error("operational_incident_not_recorded", kind, error instanceof Error ? error.message : error);
  }
}

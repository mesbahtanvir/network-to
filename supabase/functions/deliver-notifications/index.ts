// Delivers queued notification events through APNs.
// Invoked every minute by the database schedule (pg_cron + pg_net) with a
// shared job secret. The database claims the batch and records every outcome;
// this function only performs the transport with the server-side APNs key.
import { jsonResponse, requiredEnvironment, secretsMatch } from "../_shared/http.ts";
import {
  apnsPayload,
  type ClaimedNotification,
  importProviderKey,
  notificationContent,
  ProviderTokenCache,
  sendToDevice,
} from "../_shared/apns.ts";
import { bundleID } from "../_shared/app_store_membership.ts";

const batchSize = 50;

interface APNsConfiguration {
  tokens: ProviderTokenCache;
  topic: string;
}

let configuration: APNsConfiguration | undefined;

async function loadConfiguration(): Promise<APNsConfiguration | null> {
  if (configuration) return configuration;
  const keyID = Deno.env.get("APNS_KEY_ID")?.trim();
  const teamID = Deno.env.get("APNS_TEAM_ID")?.trim();
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyID || !teamID || !privateKey?.trim()) return null;
  const key = await importProviderKey(privateKey);
  configuration = {
    tokens: new ProviderTokenCache(key, keyID, teamID),
    topic: Deno.env.get("APNS_BUNDLE_ID")?.trim() || bundleID,
  };
  return configuration;
}

function serviceHeaders(): Record<string, string> {
  const key = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
  return { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json" };
}

async function rpc(name: string, body: unknown): Promise<Response> {
  const url = requiredEnvironment("SUPABASE_URL");
  return await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: serviceHeaders(),
    body: JSON.stringify(body),
  });
}

async function complete(eventID: string, delivered: boolean, error?: string): Promise<void> {
  const response = await rpc("complete_notification_delivery", {
    p_event_id: eventID,
    p_delivered: delivered,
    p_error: error ?? null,
  });
  if (!response.ok) console.error("notification_completion_failed", eventID, response.status);
  await response.body?.cancel();
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  const expectedSecret = Deno.env.get("NOTIFICATION_JOB_SECRET") ?? "";
  if (!(await secretsMatch(request.headers.get("x-job-secret") ?? "", expectedSecret))) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  try {
    const claimResponse = await rpc("claim_notification_deliveries", { p_limit: batchSize });
    if (!claimResponse.ok) return jsonResponse({ error: "Could not claim notifications" }, 500);
    const events = await claimResponse.json() as ClaimedNotification[];
    if (!Array.isArray(events) || events.length === 0) return jsonResponse({ claimed: 0, delivered: 0 });

    let apns: APNsConfiguration | null;
    try {
      apns = await loadConfiguration();
    } catch (error) {
      const detail = error instanceof Error ? error.message : "Invalid APNs configuration";
      for (const event of events) await complete(event.id, false, `APNs configuration error: ${detail}`);
      return jsonResponse({ error: "APNs configuration is invalid", claimed: events.length }, 500);
    }
    if (!apns) {
      for (const event of events) await complete(event.id, false, "APNs is not configured");
      return jsonResponse({ status: "configuration_required", claimed: events.length, delivered: 0 }, 503);
    }

    const summary = { claimed: events.length, delivered: 0, failed: 0, retired_tokens: 0, aborted: false };
    const expirationSeconds = Math.floor(Date.now() / 1000) + 24 * 60 * 60;

    for (const event of events) {
      if (summary.aborted) {
        await complete(event.id, false, "Delivery run stopped after APNs rejected the provider token");
        summary.failed += 1;
        continue;
      }
      const payload = event.payload ?? {};
      const content = notificationContent(event.kind, event.counterpart_first_name, payload);
      if (!content) {
        await complete(event.id, false, `Unsupported notification kind: ${event.kind}`);
        summary.failed += 1;
        continue;
      }
      const body = apnsPayload(event.kind, content, payload);

      let delivered = false;
      let lastReason = "No registered devices";
      for (const device of event.devices ?? []) {
        const result = await sendToDevice({
          token: device.token,
          environment: device.environment,
          topic: apns.topic,
          providerToken: await apns.tokens.token(),
          payload: body,
          content,
          expirationSeconds,
        });
        if (result.outcome === "delivered") {
          delivered = true;
          continue;
        }
        lastReason = `${result.reason} (${device.environment})`;
        if (result.outcome === "invalid_token") {
          const retired = await rpc("retire_device_token", { p_token: device.token });
          if (retired.ok) summary.retired_tokens += 1;
          await retired.body?.cancel();
        } else if (result.outcome === "auth_failed") {
          apns.tokens.invalidate();
          summary.aborted = true;
          console.error("apns_provider_token_rejected", result.reason);
          break;
        }
      }

      if (delivered) {
        summary.delivered += 1;
        await complete(event.id, true);
      } else {
        summary.failed += 1;
        await complete(event.id, false, lastReason);
      }
    }

    return jsonResponse(summary, summary.aborted ? 502 : 200);
  } catch (error) {
    if (error instanceof Response) return error;
    console.error("notification_delivery_failed", error);
    return jsonResponse({ error: error instanceof Error ? error.message : "Unexpected error" }, 500);
  }
});

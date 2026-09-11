// Receives App Store Server Notifications v2 so membership stays accurate while
// the app is closed. Apple authenticates by signature, not by Supabase JWT:
// every payload is verified against Apple's certificate chain, bundle ID, and
// environment before the database applies it idempotently.
import { jsonResponse, requiredEnvironment } from "../_shared/http.ts";
import { appAccountTokenUUID, claimedEnvironment, deriveMembershipChange } from "../_shared/app_store_membership.ts";
import { makeVerifier } from "../_shared/app_store.ts";

const maximumPayloadBytes = 65_536;

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (contentLength > maximumPayloadBytes) return jsonResponse({ error: "Request too large" }, 413);

  let signedPayload: unknown;
  try {
    const body = await request.json();
    signedPayload = body?.signedPayload;
  } catch {
    return jsonResponse({ error: "A JSON body with signedPayload is required" }, 400);
  }
  if (typeof signedPayload !== "string" || signedPayload.length < 32 || signedPayload.length > maximumPayloadBytes) {
    return jsonResponse({ error: "A signed notification payload is required" }, 400);
  }

  const environmentClaim = claimedEnvironment(signedPayload);
  if (!environmentClaim) return jsonResponse({ error: "Unsupported App Store environment" }, 400);

  try {
    const verifier = await makeVerifier(environmentClaim);
    const notification = await verifier.verifyAndDecodeNotification(signedPayload);
    const transaction = notification.data?.signedTransactionInfo
      ? await verifier.verifyAndDecodeTransaction(notification.data.signedTransactionInfo)
      : undefined;
    const renewal = notification.data?.signedRenewalInfo
      ? await verifier.verifyAndDecodeRenewalInfo(notification.data.signedRenewalInfo)
      : undefined;

    if (!notification.notificationUUID || !notification.signedDate) {
      return jsonResponse({ error: "The notification is incomplete" }, 400);
    }

    const change = deriveMembershipChange(
      notification.notificationType ? String(notification.notificationType) : undefined,
      transaction,
      renewal,
      Date.now(),
    );

    const url = requiredEnvironment("SUPABASE_URL");
    const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
    const rpcResponse = await fetch(`${url}/rest/v1/rpc/record_app_store_notification`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        p_notification_uuid: notification.notificationUUID,
        p_notification_type: String(notification.notificationType ?? "UNKNOWN"),
        p_subtype: notification.subtype ? String(notification.subtype) : null,
        p_environment: environmentClaim.toLowerCase(),
        p_signed_at: new Date(notification.signedDate).toISOString(),
        p_original_transaction_id: transaction?.originalTransactionId ?? null,
        p_latest_transaction_id: transaction?.transactionId ?? null,
        p_app_account_token: appAccountTokenUUID(transaction?.appAccountToken),
        p_product_id: transaction?.productId ?? null,
        p_status: change?.status ?? null,
        p_access_ends_at: change?.accessEndsAt ?? null,
        p_auto_renews: change?.autoRenews ?? null,
      }),
    });
    if (!rpcResponse.ok) {
      console.error("app_store_notification_not_recorded", rpcResponse.status);
      return jsonResponse({ error: "Could not record the notification" }, 500);
    }
    const outcome = await rpcResponse.json();
    return jsonResponse({ status: outcome });
  } catch (error) {
    if (error instanceof Response) return error;
    console.error("app_store_notification_rejected", error instanceof Error ? error.message : error);
    return jsonResponse({ error: "The notification could not be verified" }, 401);
  }
});

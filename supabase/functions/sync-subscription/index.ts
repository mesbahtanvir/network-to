import { authenticatedUser, jsonResponse, requiredEnvironment } from "../_shared/http.ts";
import { claimedEnvironment, productID } from "../_shared/app_store_membership.ts";
import { makeVerifier } from "../_shared/app_store.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const user = await authenticatedUser(request);
    const body = await request.json();
    const signedTransaction = body?.signed_transaction;
    if (typeof signedTransaction !== "string" || signedTransaction.length > 32_000) {
      return jsonResponse({ error: "A valid signed transaction is required" }, 400);
    }

    const environmentClaim = claimedEnvironment(signedTransaction);
    if (!environmentClaim) {
      return jsonResponse({ error: "Only App Store sandbox or production transactions can be synchronized" }, 422);
    }

    const verifier = await makeVerifier(environmentClaim);
    const transaction = await verifier.verifyAndDecodeTransaction(signedTransaction);

    if (transaction.productId !== productID) {
      return jsonResponse({ error: "Unsupported product" }, 422);
    }
    if (transaction.appAccountToken?.toLowerCase() !== user.id.toLowerCase()) {
      return jsonResponse({ error: "This purchase belongs to a different network.to account" }, 403);
    }
    if (!transaction.transactionId || !transaction.originalTransactionId || !transaction.expiresDate) {
      return jsonResponse({ error: "The App Store transaction is incomplete" }, 422);
    }

    const now = Date.now();
    const status = transaction.revocationDate
      ? "revoked"
      : transaction.expiresDate > now
      ? "active"
      : "expired";
    const url = requiredEnvironment("SUPABASE_URL");
    const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY");
    const rpcResponse = await fetch(`${url}/rest/v1/rpc/record_app_store_entitlement`, {
      method: "POST",
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        p_user_id: user.id,
        p_product_id: transaction.productId,
        p_original_transaction_id: transaction.originalTransactionId,
        p_latest_transaction_id: transaction.transactionId,
        p_status: status,
        p_access_ends_at: new Date(transaction.expiresDate).toISOString(),
        p_auto_renews: false,
        p_environment: environmentClaim.toLowerCase(),
      }),
    });
    if (!rpcResponse.ok) {
      return jsonResponse({ error: "Could not update membership access" }, 500);
    }

    return jsonResponse({ state: status === "active" ? "subscribed" : "expired" });
  } catch (error) {
    if (error instanceof Response) return error;
    console.error("subscription_sync_failed", error);
    return jsonResponse({ error: "The App Store transaction could not be verified" }, 422);
  }
});

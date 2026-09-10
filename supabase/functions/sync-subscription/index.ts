import {
  Environment,
  SignedDataVerifier,
} from "npm:@apple/app-store-server-library@3.1.0";
import { Buffer } from "node:buffer";
import { authenticatedUser, jsonResponse, requiredEnvironment } from "../_shared/http.ts";

const bundleID = "com.mesbahtanvir.networkto";
const productID = "com.mesbahtanvir.networkto.monthly";
const appleRoots = [
  "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
];

let rootsPromise: Promise<Buffer[]> | undefined;

function loadAppleRoots(): Promise<Buffer[]> {
  rootsPromise ??= Promise.all(appleRoots.map(async (url) => {
    const response = await fetch(url);
    if (!response.ok) throw new Error("Could not load Apple trust roots");
    return Buffer.from(await response.arrayBuffer());
  }));
  return rootsPromise;
}

function claimedEnvironment(jws: string): string | undefined {
  try {
    const payload = jws.split(".")[1];
    if (!payload) return undefined;
    const normalized = payload.replaceAll("-", "+").replaceAll("_", "/");
    const decoded = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    return decoded.environment;
  } catch {
    return undefined;
  }
}

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
    if (environmentClaim !== "Sandbox" && environmentClaim !== "Production") {
      return jsonResponse({ error: "Only App Store sandbox or production transactions can be synchronized" }, 422);
    }

    const environment = environmentClaim === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
    const appAppleID = environment === Environment.PRODUCTION
      ? Number(requiredEnvironment("APPLE_APP_ID"))
      : undefined;
    if (environment === Environment.PRODUCTION && !Number.isSafeInteger(appAppleID)) {
      throw new Error("APPLE_APP_ID must be a numeric App Store application identifier");
    }

    const verifier = new SignedDataVerifier(
      await loadAppleRoots(),
      true,
      environment,
      bundleID,
      appAppleID,
    );
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

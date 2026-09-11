// Pure App Store helpers shared by sync-subscription and app-store-notifications.
// Nothing here talks to Apple or Supabase, so it is unit-tested with `deno test`.

export const bundleID = "com.mesbahtanvir.networkto";
export const productID = "com.mesbahtanvir.networkto.monthly";

export type AppleEnvironmentClaim = "Sandbox" | "Production";

/**
 * Reads the environment claim from an unverified JWS payload so the matching
 * verifier can be chosen. The verifier then enforces the claim cryptographically.
 */
export function claimedEnvironment(jws: string): AppleEnvironmentClaim | undefined {
  try {
    const payload = jws.split(".")[1];
    if (!payload) return undefined;
    const normalized = payload.replaceAll("-", "+").replaceAll("_", "/");
    const decoded = JSON.parse(atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")));
    const claim = decoded?.environment ?? decoded?.data?.environment;
    return claim === "Sandbox" || claim === "Production" ? claim : undefined;
  } catch {
    return undefined;
  }
}

export type MembershipStatus = "active" | "grace_period" | "billing_retry" | "expired" | "revoked";

export interface TransactionFacts {
  productId?: string;
  transactionId?: string;
  originalTransactionId?: string;
  appAccountToken?: string;
  expiresDate?: number;
  revocationDate?: number;
}

export interface RenewalFacts {
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
  isInBillingRetryPeriod?: boolean;
}

export interface MembershipChange {
  status: MembershipStatus;
  accessEndsAt: string;
  autoRenews: boolean;
}

/** Notification types whose signed transaction and renewal info describe the member's current entitlement. */
const entitlementNotificationTypes = new Set([
  "SUBSCRIBED",
  "DID_RENEW",
  "DID_CHANGE_RENEWAL_STATUS",
  "DID_CHANGE_RENEWAL_PREF",
  "DID_FAIL_TO_RENEW",
  "EXPIRED",
  "GRACE_PERIOD_EXPIRED",
  "OFFER_REDEEMED",
  "PRICE_INCREASE",
  "RENEWAL_EXTENDED",
  "REFUND",
  "REFUND_REVERSED",
  "REVOKE",
]);

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function appAccountTokenUUID(value: unknown): string | null {
  return typeof value === "string" && uuidPattern.test(value) ? value.toLowerCase() : null;
}

/**
 * Derives the membership state a notification implies. Returns null for
 * informational notifications, other products, or payloads without a
 * subscription transaction, which the database then records as ignored.
 */
export function deriveMembershipChange(
  notificationType: string | undefined,
  transaction: TransactionFacts | undefined,
  renewal: RenewalFacts | undefined,
  now: number = Date.now(),
): MembershipChange | null {
  if (!notificationType || !entitlementNotificationTypes.has(notificationType) || !transaction) return null;
  if (transaction.productId !== productID) return null;
  if (transaction.expiresDate === undefined && transaction.revocationDate === undefined) return null;

  const autoRenews = renewal?.autoRenewStatus === 1;
  const expiresDate = transaction.expiresDate ?? now;

  if (notificationType === "REFUND" || notificationType === "REVOKE" || transaction.revocationDate !== undefined) {
    return { status: "revoked", accessEndsAt: isoDate(transaction.revocationDate ?? now), autoRenews: false };
  }
  if (renewal?.gracePeriodExpiresDate !== undefined && renewal.gracePeriodExpiresDate > now) {
    return { status: "grace_period", accessEndsAt: isoDate(renewal.gracePeriodExpiresDate), autoRenews };
  }
  if (expiresDate > now) {
    return { status: "active", accessEndsAt: isoDate(expiresDate), autoRenews };
  }
  if (renewal?.isInBillingRetryPeriod) {
    return { status: "billing_retry", accessEndsAt: isoDate(expiresDate), autoRenews };
  }
  return { status: "expired", accessEndsAt: isoDate(expiresDate), autoRenews: false };
}

function isoDate(milliseconds: number): string {
  return new Date(milliseconds).toISOString();
}

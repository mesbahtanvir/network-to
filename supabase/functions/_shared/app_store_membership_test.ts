import { assertEquals } from "jsr:@std/assert@1";
import { appAccountTokenUUID, claimedEnvironment, deriveMembershipChange, productID } from "./app_store_membership.ts";

const now = Date.parse("2026-09-11T12:00:00Z");
const hour = 3_600_000;
const day = 24 * hour;

const monthly = {
  productId: productID,
  transactionId: "2000000900000002",
  originalTransactionId: "2000000900000001",
  appAccountToken: "10000000-0000-0000-0000-000000000001",
  expiresDate: now + 30 * day,
};

function jws(payload: unknown): string {
  const encode = (value: unknown) => btoa(JSON.stringify(value)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  return `${encode({ alg: "ES256" })}.${encode(payload)}.signature`;
}

Deno.test("a renewal keeps access until the new expiry date", () => {
  assertEquals(deriveMembershipChange("DID_RENEW", monthly, { autoRenewStatus: 1 }, now), {
    status: "active",
    accessEndsAt: new Date(now + 30 * day).toISOString(),
    autoRenews: true,
  });
});

Deno.test("turning off auto-renew keeps access but records the intent", () => {
  assertEquals(deriveMembershipChange("DID_CHANGE_RENEWAL_STATUS", monthly, { autoRenewStatus: 0 }, now), {
    status: "active",
    accessEndsAt: new Date(now + 30 * day).toISOString(),
    autoRenews: false,
  });
});

Deno.test("a billing grace period keeps access until the grace period ends", () => {
  const change = deriveMembershipChange(
    "DID_FAIL_TO_RENEW",
    { ...monthly, expiresDate: now - hour },
    { autoRenewStatus: 1, gracePeriodExpiresDate: now + 16 * day, isInBillingRetryPeriod: true },
    now,
  );
  assertEquals(change, { status: "grace_period", accessEndsAt: new Date(now + 16 * day).toISOString(), autoRenews: true });
});

Deno.test("billing retry without a grace period ends access at the expiry date", () => {
  const change = deriveMembershipChange(
    "DID_FAIL_TO_RENEW",
    { ...monthly, expiresDate: now - hour },
    { autoRenewStatus: 1, isInBillingRetryPeriod: true },
    now,
  );
  assertEquals(change, { status: "billing_retry", accessEndsAt: new Date(now - hour).toISOString(), autoRenews: true });
});

Deno.test("an expired subscription is recorded as expired without auto-renew", () => {
  const change = deriveMembershipChange("EXPIRED", { ...monthly, expiresDate: now - day }, { autoRenewStatus: 0 }, now);
  assertEquals(change, { status: "expired", accessEndsAt: new Date(now - day).toISOString(), autoRenews: false });
});

Deno.test("a refund revokes access at the revocation date", () => {
  const change = deriveMembershipChange("REFUND", { ...monthly, revocationDate: now - hour }, { autoRenewStatus: 1 }, now);
  assertEquals(change, { status: "revoked", accessEndsAt: new Date(now - hour).toISOString(), autoRenews: false });
});

Deno.test("a revoked transaction is revoked whatever notification carries it", () => {
  const change = deriveMembershipChange("DID_RENEW", { ...monthly, revocationDate: now - hour }, { autoRenewStatus: 1 }, now);
  assertEquals(change?.status, "revoked");
});

Deno.test("a reversed refund reinstates access from the transaction", () => {
  const change = deriveMembershipChange("REFUND_REVERSED", monthly, { autoRenewStatus: 1 }, now);
  assertEquals(change?.status, "active");
});

Deno.test("informational notifications imply no membership change", () => {
  assertEquals(deriveMembershipChange("TEST", undefined, undefined, now), null);
  assertEquals(deriveMembershipChange("CONSUMPTION_REQUEST", monthly, undefined, now), null);
  assertEquals(deriveMembershipChange(undefined, monthly, undefined, now), null);
});

Deno.test("other products never change membership", () => {
  assertEquals(deriveMembershipChange("SUBSCRIBED", { ...monthly, productId: "com.example.other" }, undefined, now), null);
});

Deno.test("the environment claim is read from transactions and notifications alike", () => {
  assertEquals(claimedEnvironment(jws({ environment: "Sandbox" })), "Sandbox");
  assertEquals(claimedEnvironment(jws({ data: { environment: "Production" } })), "Production");
  assertEquals(claimedEnvironment(jws({ environment: "Xcode" })), undefined);
  assertEquals(claimedEnvironment("not-a-jws"), undefined);
});

Deno.test("only UUID app account tokens are forwarded", () => {
  assertEquals(appAccountTokenUUID("10000000-0000-0000-0000-000000000001"), "10000000-0000-0000-0000-000000000001");
  assertEquals(appAccountTokenUUID("10000000-0000-0000-0000-00000000000X"), null);
  assertEquals(appAccountTokenUUID(undefined), null);
});

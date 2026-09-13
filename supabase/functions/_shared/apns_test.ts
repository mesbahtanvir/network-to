import { assert, assertEquals, assertNotEquals, assertThrows } from "jsr:@std/assert@1";
import {
  apnsHost,
  apnsPayload,
  base64urlDecode,
  createProviderToken,
  importProviderKey,
  interpretResponse,
  notificationContent,
  privateKeyDER,
  ProviderTokenCache,
} from "./apns.ts";

const decoder = new TextDecoder();
const encoder = new TextEncoder();

Deno.test("new message notifications name the sender and never include the message", () => {
  const content = notificationContent("new_message", "Priya", { conversation_id: "c1", message_id: "m1" });
  assertEquals(content?.title, "New message");
  assertEquals(content?.body, "Priya sent you a message.");
  assertEquals(content?.threadId, "c1");
  assertEquals(content?.collapseId, "message:c1");
});

Deno.test("pending introductions stay anonymous", () => {
  const content = notificationContent("introduction_ready", "Priya", { introduction_id: "i1" });
  assert(content);
  assert(!content.body.includes("Priya"));
  assertEquals(content.collapseId, "introduction:i1");
});

Deno.test("copy degrades gracefully without a first name", () => {
  assertEquals(notificationContent("mutual_interest", null, {})?.body, "You are both interested in meeting. You can now message each other.");
  assertEquals(notificationContent("feedback_due", "", { meetup_id: "m1" })?.collapseId, "feedback:m1");
  assertEquals(notificationContent("meetup_reminder", "Priya", {})?.priority, 5);
});

Deno.test("unknown kinds produce no notification", () => {
  assertEquals(notificationContent("marketing", "Priya", {}), null);
});

Deno.test("payloads carry only identifiers the app can open", () => {
  const content = notificationContent("new_message", "Priya", { conversation_id: "c1" })!;
  const payload = apnsPayload("new_message", content, { conversation_id: "c1", message_id: "m1", body: "secret" });
  assertEquals(payload.conversation_id, "c1");
  assertEquals("message_id" in payload, false);
  assertEquals("body" in payload, false);
  const aps = payload.aps as Record<string, unknown>;
  assertEquals(aps.alert, { title: "New message", body: "Priya sent you a message." });
  assertEquals(aps["thread-id"], "c1");
});

Deno.test("APNs responses map to delivery outcomes", () => {
  assertEquals(interpretResponse(200, undefined).outcome, "delivered");
  assertEquals(interpretResponse(410, "Unregistered").outcome, "invalid_token");
  assertEquals(interpretResponse(400, "BadDeviceToken").outcome, "invalid_token");
  assertEquals(interpretResponse(403, "ExpiredProviderToken").outcome, "auth_failed");
  assertEquals(interpretResponse(429, "TooManyRequests").outcome, "retry");
  assertEquals(interpretResponse(503, undefined).outcome, "retry");
  assertEquals(interpretResponse(400, "BadTopic").outcome, "rejected");
  assertEquals(interpretResponse(400, "BadTopic").reason, "BadTopic");
});

Deno.test("sandbox and production tokens use their own APNs hosts", () => {
  assertEquals(apnsHost("sandbox"), "https://api.sandbox.push.apple.com");
  assertEquals(apnsHost("production"), "https://api.push.apple.com");
});

async function generatePEM(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of pkcs8) binary += String.fromCharCode(byte);
  const lines = btoa(binary).match(/.{1,64}/g) ?? [];
  return { pem: `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

Deno.test("provider tokens are ES256 JWTs signed by the .p8 key, even when stored with escaped newlines", async () => {
  const { pem, publicKey } = await generatePEM();
  const key = await importProviderKey(pem.replaceAll("\n", "\\n"));
  const token = await createProviderToken(key, "KEY1234567", "TEAM123456", 1_800_000_000);
  const [header, claims, signature] = token.split(".");
  assertEquals(JSON.parse(decoder.decode(base64urlDecode(header))), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(JSON.parse(decoder.decode(base64urlDecode(claims))), { iss: "TEAM123456", iat: 1_800_000_000 });
  assertEquals(base64urlDecode(signature).length, 64);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    publicKey,
    base64urlDecode(signature),
    encoder.encode(`${header}.${claims}`),
  );
  assert(valid);
});

Deno.test("provider tokens are reused within their lifetime and refreshed afterwards", async () => {
  const { pem } = await generatePEM();
  const cache = new ProviderTokenCache(await importProviderKey(pem), "KEY", "TEAM", 3000);
  const first = await cache.token(1_000);
  assertEquals(await cache.token(2_000), first);
  const refreshed = await cache.token(4_001);
  assertNotEquals(refreshed, first);
  cache.invalidate();
  assertNotEquals(await cache.token(4_001), "");
});

Deno.test("an empty private key is rejected before any delivery attempt", () => {
  assertThrows(() => privateKeyDER("-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----"));
});

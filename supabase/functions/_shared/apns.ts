// Apple Push Notification service transport helpers.
// Pure functions (content, payload, response interpretation, provider tokens)
// are unit-tested; only sendToDevice performs network I/O.

export interface ClaimedNotification {
  id: string;
  user_id: string;
  kind: string;
  payload: Record<string, unknown>;
  counterpart_first_name: string | null;
  devices: Array<{ token: string; environment: string }>;
}

export interface NotificationContent {
  title: string;
  body: string;
  threadId: string;
  collapseId: string;
  priority: 5 | 10;
}

function idFrom(payload: Record<string, unknown>, key: string): string | null {
  const value = payload[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

/**
 * Notification copy is scarce and calm by design: no message bodies, no
 * rejection notices, and the other member's first name only once a
 * relationship already exists. A pending introduction stays anonymous.
 */
export function notificationContent(
  kind: string,
  firstName: string | null,
  payload: Record<string, unknown>,
): NotificationContent | null {
  const name = firstName?.trim() || null;
  const conversationID = idFrom(payload, "conversation_id");
  const introductionID = idFrom(payload, "introduction_id");
  const meetupID = idFrom(payload, "meetup_id");

  switch (kind) {
    case "introduction_ready":
      return {
        title: "A new introduction is ready",
        body: "Someone in your city may be worth meeting. Take a look when you have a moment.",
        threadId: introductionID ?? "introductions",
        collapseId: `introduction:${introductionID ?? "next"}`.slice(0, 64),
        priority: 10,
      };
    case "mutual_interest":
      return {
        title: "Mutual interest",
        body: name
          ? `${name} is interested in meeting too. You can now message each other.`
          : "You are both interested in meeting. You can now message each other.",
        threadId: conversationID ?? introductionID ?? "conversations",
        collapseId: `mutual:${introductionID ?? conversationID ?? "next"}`.slice(0, 64),
        priority: 10,
      };
    case "new_message":
      return {
        title: "New message",
        body: name ? `${name} sent you a message.` : "You have a new message.",
        threadId: conversationID ?? "conversations",
        collapseId: `message:${conversationID ?? "next"}`.slice(0, 64),
        priority: 10,
      };
    case "meetup_reminder":
      return {
        title: "Your 1:1 is coming up",
        body: name
          ? `Your meeting with ${name} is coming up. The details are in Messages.`
          : "Your meeting is coming up. The details are in Messages.",
        threadId: conversationID ?? "conversations",
        collapseId: `meetup:${meetupID ?? conversationID ?? "next"}`.slice(0, 64),
        priority: 5,
      };
    case "feedback_due":
      return {
        title: "How did it go?",
        body: name
          ? `Share private feedback on meeting ${name} and decide whether to stay connected.`
          : "Share private feedback on your meeting and decide whether to stay connected.",
        threadId: conversationID ?? "conversations",
        collapseId: `feedback:${meetupID ?? conversationID ?? "next"}`.slice(0, 64),
        priority: 5,
      };
    default:
      return null;
  }
}

export function apnsPayload(kind: string, content: NotificationContent, payload: Record<string, unknown>): Record<string, unknown> {
  const body: Record<string, unknown> = {
    aps: {
      alert: { title: content.title, body: content.body },
      sound: "default",
      "thread-id": content.threadId,
      "interruption-level": "active",
    },
    kind,
  };
  for (const key of ["introduction_id", "conversation_id", "meetup_id"]) {
    const value = idFrom(payload, key);
    if (value) body[key] = value;
  }
  return body;
}

export type DeliveryOutcome = "delivered" | "invalid_token" | "retry" | "auth_failed" | "rejected";

export interface DeliveryResult {
  outcome: DeliveryOutcome;
  reason: string;
  status: number;
}

const invalidTokenReasons = new Set(["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered", "ExpiredToken"]);
const providerTokenReasons = new Set(["ExpiredProviderToken", "InvalidProviderToken", "MissingProviderToken"]);

export function interpretResponse(status: number, reason: string | undefined): DeliveryResult {
  const detail = reason ?? `HTTP ${status}`;
  if (status === 200) return { outcome: "delivered", reason: "OK", status };
  if (status === 410 || (reason !== undefined && invalidTokenReasons.has(reason))) {
    return { outcome: "invalid_token", reason: detail, status };
  }
  if (status === 403 || (reason !== undefined && providerTokenReasons.has(reason))) {
    return { outcome: "auth_failed", reason: detail, status };
  }
  if (status === 429 || status >= 500) return { outcome: "retry", reason: detail, status };
  return { outcome: "rejected", reason: detail, status };
}

export function apnsHost(environment: string): string {
  return environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
}

const base64urlAlphabet = /^[A-Za-z0-9_-]+$/;

export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function base64urlDecode(value: string): Uint8Array<ArrayBuffer> {
  if (!base64urlAlphabet.test(value)) throw new Error("Invalid base64url input");
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

/** Accepts the .p8 contents as stored in a secret, including escaped newlines. */
export function privateKeyDER(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replaceAll("\\n", "\n")
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----/g, "")
    .replace(/-----END [A-Z ]*PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  if (!body) throw new Error("APNS_PRIVATE_KEY is empty");
  return Uint8Array.from(atob(body), (character) => character.charCodeAt(0));
}

export async function importProviderKey(pem: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "pkcs8",
    privateKeyDER(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

export async function createProviderToken(
  key: CryptoKey,
  keyID: string,
  teamID: string,
  issuedAt: number = Math.floor(Date.now() / 1000),
): Promise<string> {
  const encoder = new TextEncoder();
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyID })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: teamID, iat: issuedAt })));
  const signingInput = `${header}.${claims}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

/** Apple requires provider tokens to be refreshed at least hourly and at most every twenty minutes. */
export class ProviderTokenCache {
  #token: string | undefined;
  #issuedAt = 0;

  constructor(
    private readonly key: CryptoKey,
    private readonly keyID: string,
    private readonly teamID: string,
    private readonly lifetimeSeconds = 50 * 60,
  ) {}

  async token(now: number = Math.floor(Date.now() / 1000)): Promise<string> {
    if (!this.#token || now - this.#issuedAt >= this.lifetimeSeconds) {
      this.#token = await createProviderToken(this.key, this.keyID, this.teamID, now);
      this.#issuedAt = now;
    }
    return this.#token;
  }

  invalidate(): void {
    this.#token = undefined;
    this.#issuedAt = 0;
  }
}

export interface DeviceDelivery {
  token: string;
  environment: string;
  topic: string;
  providerToken: string;
  payload: Record<string, unknown>;
  content: NotificationContent;
  expirationSeconds: number;
}

export async function sendToDevice(delivery: DeviceDelivery): Promise<DeliveryResult> {
  try {
    const response = await fetch(`${apnsHost(delivery.environment)}/3/device/${delivery.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${delivery.providerToken}`,
        "apns-topic": delivery.topic,
        "apns-push-type": "alert",
        "apns-priority": String(delivery.content.priority),
        "apns-expiration": String(delivery.expirationSeconds),
        "apns-collapse-id": delivery.content.collapseId,
        "content-type": "application/json",
      },
      body: JSON.stringify(delivery.payload),
    });
    let reason: string | undefined;
    if (response.status !== 200) {
      try {
        const body = await response.json();
        if (body && typeof body.reason === "string") reason = body.reason;
      } catch {
        reason = undefined;
      }
    } else {
      await response.body?.cancel();
    }
    return interpretResponse(response.status, reason);
  } catch (error) {
    return { outcome: "retry", reason: error instanceof Error ? error.message : "Network error", status: 0 };
  }
}

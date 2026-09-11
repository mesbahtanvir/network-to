// Apple signature verification shared by sync-subscription and app-store-notifications.
import { Environment, SignedDataVerifier } from "npm:@apple/app-store-server-library@3.1.0";
import { Buffer } from "node:buffer";
import { requiredEnvironment } from "./http.ts";
import { type AppleEnvironmentClaim, bundleID } from "./app_store_membership.ts";

const appleRoots = [
  "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G2.cer",
  "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
];

let rootsPromise: Promise<Buffer[]> | undefined;

export function loadAppleRoots(): Promise<Buffer[]> {
  rootsPromise ??= Promise.all(appleRoots.map(async (url) => {
    const response = await fetch(url);
    if (!response.ok) throw new Error("Could not load Apple trust roots");
    return Buffer.from(await response.arrayBuffer());
  })).catch((error) => {
    // A transient download failure must not poison every later request of this instance.
    rootsPromise = undefined;
    throw error;
  });
  return rootsPromise;
}

export async function makeVerifier(environmentClaim: AppleEnvironmentClaim): Promise<SignedDataVerifier> {
  const environment = environmentClaim === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
  const appAppleID = environment === Environment.PRODUCTION
    ? Number(requiredEnvironment("APPLE_APP_ID"))
    : undefined;
  if (environment === Environment.PRODUCTION && !Number.isSafeInteger(appAppleID)) {
    throw new Error("APPLE_APP_ID must be a numeric App Store application identifier");
  }
  return new SignedDataVerifier(await loadAppleRoots(), true, environment, bundleID, appAppleID);
}

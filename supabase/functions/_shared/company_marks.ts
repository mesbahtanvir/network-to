// Pure logic for the company-marks operations action: discovering the icons a company
// publishes on its own website, reading image headers, and choosing the mark to serve.
// Nothing here performs network or storage I/O; index.ts owns transport.

export const maxMarkBytes = 1_048_576;
export const minMarkSide = 128;
export const maxCandidates = 8;

export type ImageKind = "png" | "jpeg" | "ico";

export interface ImageInfo {
  kind: ImageKind;
  width: number;
  height: number;
  animated: boolean;
}

export type CandidateSource = "link" | "manifest" | "fallback";

export interface IconCandidate {
  url: string;
  declaredSize: number | null;
  source: CandidateSource;
}

export type FetchFailureReason = "unreachable" | "too_large" | "wrong_kind" | "upload_failed";

export interface DecodedCandidate {
  url: string;
  bytes: Uint8Array;
  info: ImageInfo;
}

export type MarkChoice =
  | { outcome: "fetched"; candidate: DecodedCandidate }
  | { outcome: "no_icon_published"; reason: string }
  | { outcome: "fetch_failed"; reason: FetchFailureReason };

const iconRelations = new Set([
  "icon",
  "shortcut icon",
  "apple-touch-icon",
  "apple-touch-icon-precomposed",
  "mask-icon",
]);

/** Only public http(s) hosts; never IP literals or loopback names. */
export function isSafeIconURL(raw: string): boolean {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return false;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return false;
  const host = url.hostname.toLowerCase();
  if (!host || host === "localhost" || host.endsWith(".localhost") || host.endsWith(".local")) return false;
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return false;
  if (host.startsWith("[") || host.includes(":")) return false;
  if (url.username || url.password) return false;
  return true;
}

function parseAttributes(tag: string): Record<string, string> {
  const attributes: Record<string, string> = {};
  const pattern = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
  const body = tag.replace(/^<link\b/i, "").replace(/\/?>$/, "");
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(body)) !== null) {
    const name = match[1].toLowerCase();
    const value = match[2] ?? match[3] ?? match[4] ?? "";
    attributes[name] = decodeEntities(value.trim());
  }
  return attributes;
}

function decodeEntities(value: string): string {
  return value
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">");
}

/** "180x180" or "192x192 512x512" → largest declared side; "any" or missing → null. */
export function parseDeclaredSize(sizes: string | undefined): number | null {
  if (!sizes) return null;
  let largest = 0;
  for (const token of sizes.toLowerCase().split(/\s+/)) {
    const match = /^(\d{1,5})x(\d{1,5})$/.exec(token);
    if (!match) continue;
    largest = Math.max(largest, Math.min(Number(match[1]), Number(match[2])));
  }
  return largest > 0 ? largest : null;
}

function resolve(href: string, base: string): string | null {
  try {
    return new URL(href, base).toString();
  } catch {
    return null;
  }
}

/** Icons declared by a web app manifest, resolved against the manifest URL. */
export function parseManifestIcons(json: string, manifestURL: string): IconCandidate[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    return [];
  }
  if (!parsed || typeof parsed !== "object") return [];
  const icons = (parsed as { icons?: unknown }).icons;
  if (!Array.isArray(icons)) return [];
  const result: IconCandidate[] = [];
  for (const icon of icons) {
    if (!icon || typeof icon !== "object") continue;
    const src = (icon as { src?: unknown }).src;
    if (typeof src !== "string" || !src.trim()) continue;
    const url = resolve(src.trim(), manifestURL);
    if (!url || !isSafeIconURL(url)) continue;
    const sizes = (icon as { sizes?: unknown }).sizes;
    result.push({ url, declaredSize: parseDeclaredSize(typeof sizes === "string" ? sizes : undefined), source: "manifest" });
  }
  return result;
}

/** The manifest link in a page, if any. */
export function manifestURL(html: string, baseURL: string): string | null {
  for (const tag of html.match(/<link\b[^>]*>/gi) ?? []) {
    const attributes = parseAttributes(tag);
    const rel = (attributes.rel ?? "").toLowerCase().split(/\s+/);
    if (!rel.includes("manifest") || !attributes.href) continue;
    const url = resolve(attributes.href, baseURL);
    if (url && isSafeIconURL(url)) return url;
  }
  return null;
}

/**
 * Icon URLs a page publishes for browsers and home screens, ordered by declared size, then the
 * conventional fallback locations; de-duplicated, unsafe URLs removed, capped at maxCandidates.
 */
export function candidateIconURLs(html: string, baseURL: string, manifestIcons: IconCandidate[] = []): IconCandidate[] {
  const declared: IconCandidate[] = [];
  for (const tag of html.match(/<link\b[^>]*>/gi) ?? []) {
    const attributes = parseAttributes(tag);
    const rel = (attributes.rel ?? "").toLowerCase().trim().replace(/\s+/g, " ");
    const relTokens = rel.split(" ");
    const isIcon = iconRelations.has(rel) || relTokens.includes("icon") || relTokens.some((token) => token.startsWith("apple-touch-icon"));
    if (!isIcon || !attributes.href) continue;
    if ((attributes.type ?? "").toLowerCase().includes("svg")) continue;
    const url = resolve(attributes.href, baseURL);
    if (!url || !isSafeIconURL(url)) continue;
    declared.push({ url, declaredSize: parseDeclaredSize(attributes.sizes), source: "link" });
  }

  const fallbacks: IconCandidate[] = [];
  for (const path of ["/apple-touch-icon.png", "/apple-touch-icon-precomposed.png", "/favicon.ico"]) {
    const url = resolve(path, baseURL);
    if (url && isSafeIconURL(url)) fallbacks.push({ url, declaredSize: null, source: "fallback" });
  }

  const bySize = (left: IconCandidate, right: IconCandidate) => (right.declaredSize ?? 0) - (left.declaredSize ?? 0);
  const ordered = [...declared, ...manifestIcons].sort(bySize).concat(fallbacks);
  const seen = new Set<string>();
  const unique: IconCandidate[] = [];
  for (const candidate of ordered) {
    if (seen.has(candidate.url)) continue;
    seen.add(candidate.url);
    unique.push(candidate);
    if (unique.length >= maxCandidates) break;
  }
  return unique;
}

function readUint32BE(bytes: Uint8Array, offset: number): number {
  return ((bytes[offset] << 24) >>> 0) + (bytes[offset + 1] << 16) + (bytes[offset + 2] << 8) + bytes[offset + 3];
}

function readUint16BE(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] << 8) + bytes[offset + 1];
}

function readUint16LE(bytes: Uint8Array, offset: number): number {
  return bytes[offset] + (bytes[offset + 1] << 8);
}

function readUint32LE(bytes: Uint8Array, offset: number): number {
  return bytes[offset] + (bytes[offset + 1] << 8) + (bytes[offset + 2] << 16) + ((bytes[offset + 3] << 24) >>> 0);
}

const pngSignature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

export function isPNG(bytes: Uint8Array): boolean {
  return bytes.length >= 8 && pngSignature.every((value, index) => bytes[index] === value);
}

function inspectPNG(bytes: Uint8Array): ImageInfo | null {
  if (bytes.length < 33) return null;
  if (String.fromCharCode(...bytes.subarray(12, 16)) !== "IHDR") return null;
  const width = readUint32BE(bytes, 16);
  const height = readUint32BE(bytes, 20);
  let animated = false;
  let position = 8;
  while (position + 8 <= bytes.length) {
    const length = readUint32BE(bytes, position);
    const type = String.fromCharCode(...bytes.subarray(position + 4, position + 8));
    if (type === "acTL") animated = true;
    if (type === "IDAT" || type === "IEND") break;
    position += 12 + length;
  }
  if (width <= 0 || height <= 0) return null;
  return { kind: "png", width, height, animated };
}

function inspectJPEG(bytes: Uint8Array): ImageInfo | null {
  if (bytes.length < 4 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let position = 2;
  while (position + 4 <= bytes.length) {
    if (bytes[position] !== 0xff) return null;
    const marker = bytes[position + 1];
    if (marker === 0xff) {
      position += 1;
      continue;
    }
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) {
      position += 2;
      continue;
    }
    if (marker === 0xd9 || marker === 0xda) return null;
    const length = readUint16BE(bytes, position + 2);
    const isFrameHeader = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isFrameHeader) {
      if (position + 9 > bytes.length) return null;
      const height = readUint16BE(bytes, position + 5);
      const width = readUint16BE(bytes, position + 7);
      if (width <= 0 || height <= 0) return null;
      return { kind: "jpeg", width, height, animated: false };
    }
    position += 2 + length;
  }
  return null;
}

/** PNG-encoded entries inside an ICO container, largest first; BMP entries are ignored. */
export function extractICOEntries(bytes: Uint8Array): Uint8Array[] {
  if (bytes.length < 6 || bytes[0] !== 0 || bytes[1] !== 0 || bytes[2] !== 1 || bytes[3] !== 0) return [];
  const count = readUint16LE(bytes, 4);
  const entries: Uint8Array[] = [];
  for (let index = 0; index < count; index += 1) {
    const entry = 6 + index * 16;
    if (entry + 16 > bytes.length) break;
    const size = readUint32LE(bytes, entry + 8);
    const offset = readUint32LE(bytes, entry + 12);
    if (size <= 0 || offset <= 0 || offset + size > bytes.length) continue;
    const payload = bytes.subarray(offset, offset + size);
    if (isPNG(payload)) entries.push(payload);
  }
  return entries.sort((left, right) => (inspectPNG(right)?.width ?? 0) - (inspectPNG(left)?.width ?? 0));
}

/** Header-only inspection; null for anything that is not a still PNG, JPEG, or ICO container. */
export function inspectImage(bytes: Uint8Array): ImageInfo | null {
  if (isPNG(bytes)) return inspectPNG(bytes);
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xd8) return inspectJPEG(bytes);
  if (bytes.length >= 6 && bytes[0] === 0 && bytes[1] === 0 && bytes[2] === 1 && bytes[3] === 0) {
    const entries = extractICOEntries(bytes);
    if (entries.length === 0) return null;
    const best = inspectPNG(entries[0]);
    return best ? { kind: "ico", width: best.width, height: best.height, animated: best.animated } : null;
  }
  return null;
}

function isSquare(info: ImageInfo): boolean {
  return Math.abs(info.width - info.height) <= Math.max(info.width, info.height) * 0.1;
}

/**
 * Largest still icon within the limits, square first. Decodable icons that are all too small
 * mean the company publishes no usable icon; nothing decodable means the fetch failed.
 */
export function chooseMark(decoded: DecodedCandidate[], failures: FetchFailureReason[]): MarkChoice {
  const usable = decoded.filter((candidate) =>
    (candidate.info.kind === "png" || candidate.info.kind === "jpeg") &&
    !candidate.info.animated &&
    Math.min(candidate.info.width, candidate.info.height) >= minMarkSide &&
    candidate.bytes.length <= maxMarkBytes
  );
  if (usable.length > 0) {
    usable.sort((left, right) => {
      const squareDelta = Number(isSquare(right.info)) - Number(isSquare(left.info));
      if (squareDelta !== 0) return squareDelta;
      const sideDelta = Math.min(right.info.width, right.info.height) - Math.min(left.info.width, left.info.height);
      if (sideDelta !== 0) return sideDelta;
      return left.bytes.length - right.bytes.length;
    });
    return { outcome: "fetched", candidate: usable[0] };
  }
  if (decoded.length > 0) {
    const largest = Math.max(...decoded.map((candidate) => Math.min(candidate.info.width, candidate.info.height)));
    const animatedOnly = decoded.every((candidate) => candidate.info.animated);
    return {
      outcome: "no_icon_published",
      reason: animatedOnly ? "only animated icons published" : `largest published icon is ${largest} px`,
    };
  }
  if (failures.length > 0) {
    const counts = new Map<FetchFailureReason, number>();
    for (const failure of failures) counts.set(failure, (counts.get(failure) ?? 0) + 1);
    const [dominant] = [...counts.entries()].sort((left, right) => right[1] - left[1])[0];
    return { outcome: "fetch_failed", reason: dominant };
  }
  return { outcome: "no_icon_published", reason: "no icon links found" };
}

export function contentTypeFor(kind: "png" | "jpeg"): "image/png" | "image/jpeg" {
  return kind === "png" ? "image/png" : "image/jpeg";
}

export function objectPath(key: string, version: number, kind: "png" | "jpeg"): string {
  return `${key}/${version}.${kind === "png" ? "png" : "jpg"}`;
}

export const companyKeyPattern = /^[a-z0-9][a-z0-9-]{0,62}$/;

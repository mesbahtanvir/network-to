import { assert, assertEquals, assertFalse } from "jsr:@std/assert@1";
import {
  candidateIconURLs,
  chooseMark,
  type DecodedCandidate,
  extractICOEntries,
  inspectImage,
  isSafeIconURL,
  manifestURL,
  objectPath,
  parseDeclaredSize,
  parseManifestIcons,
} from "./company_marks.ts";

function pngBytes(width: number, height: number, animated = false): Uint8Array {
  const chunks: number[] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  const push32 = (value: number) => chunks.push((value >>> 24) & 0xff, (value >>> 16) & 0xff, (value >>> 8) & 0xff, value & 0xff);
  const pushType = (type: string) => chunks.push(...type.split("").map((c) => c.charCodeAt(0)));
  push32(13);
  pushType("IHDR");
  push32(width);
  push32(height);
  chunks.push(8, 6, 0, 0, 0);
  push32(0);
  if (animated) {
    push32(8);
    pushType("acTL");
    push32(2);
    push32(0);
    push32(0);
  }
  push32(0);
  pushType("IDAT");
  push32(0);
  push32(0);
  pushType("IEND");
  push32(0);
  return new Uint8Array(chunks);
}

function jpegBytes(width: number, height: number): Uint8Array {
  return new Uint8Array([
    0xff, 0xd8,
    0xff, 0xe0, 0x00, 0x04, 0x00, 0x00,
    0xff, 0xc0, 0x00, 0x11, 0x08, (height >> 8) & 0xff, height & 0xff, (width >> 8) & 0xff, width & 0xff, 0x03,
    0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    0xff, 0xd9,
  ]);
}

function icoBytes(entries: Uint8Array[]): Uint8Array {
  const header = [0, 0, 1, 0, entries.length & 0xff, entries.length >> 8];
  const directory: number[] = [];
  const payloads: number[] = [];
  let offset = 6 + entries.length * 16;
  for (const entry of entries) {
    directory.push(0, 0, 0, 0, 1, 0, 32, 0);
    const size = entry.length;
    directory.push(size & 0xff, (size >> 8) & 0xff, (size >> 16) & 0xff, (size >> 24) & 0xff);
    directory.push(offset & 0xff, (offset >> 8) & 0xff, (offset >> 16) & 0xff, (offset >> 24) & 0xff);
    payloads.push(...entry);
    offset += size;
  }
  return new Uint8Array([...header, ...directory, ...payloads]);
}

const bmpEntry = new Uint8Array([40, 0, 0, 0, 16, 0, 0, 0, 32, 0, 0, 0, 1, 0, 32, 0]);

Deno.test("isSafeIconURL accepts public https hosts and rejects the rest", () => {
  assert(isSafeIconURL("https://www.shopify.com/apple-touch-icon.png"));
  assert(isSafeIconURL("http://example.com/favicon.ico"));
  assertFalse(isSafeIconURL("ftp://example.com/icon.png"));
  assertFalse(isSafeIconURL("https://127.0.0.1/icon.png"));
  assertFalse(isSafeIconURL("https://localhost/icon.png"));
  assertFalse(isSafeIconURL("https://[::1]/icon.png"));
  assertFalse(isSafeIconURL("https://user:pw@example.com/icon.png"));
  assertFalse(isSafeIconURL("not a url"));
});

Deno.test("parseDeclaredSize reads the largest declared square", () => {
  assertEquals(parseDeclaredSize("180x180"), 180);
  assertEquals(parseDeclaredSize("192x192 512x512"), 512);
  assertEquals(parseDeclaredSize("any"), null);
  assertEquals(parseDeclaredSize(undefined), null);
});

Deno.test("candidateIconURLs orders declared icons by size, adds fallbacks, and de-duplicates", () => {
  const html = `
    <html><head>
      <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">
      <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
      <link rel='shortcut icon' href='/favicon.ico'>
      <link rel="icon" type="image/svg+xml" href="/icon.svg">
      <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
      <link rel="manifest" href="/site.webmanifest">
      <link rel="icon" href="https://127.0.0.1/evil.png">
    </head></html>`;
  const manifest = parseManifestIcons(
    JSON.stringify({ icons: [{ src: "icons/icon-512.png", sizes: "512x512" }, { src: "icons/icon-192.png", sizes: "192x192" }] }),
    "https://www.example.com/site.webmanifest",
  );
  assertEquals(manifestURL(html, "https://www.example.com/"), "https://www.example.com/site.webmanifest");
  const candidates = candidateIconURLs(html, "https://www.example.com/", manifest);
  assertEquals(candidates.map((c) => c.url), [
    "https://www.example.com/icons/icon-512.png",
    "https://www.example.com/icons/icon-192.png",
    "https://www.example.com/apple-touch-icon.png",
    "https://www.example.com/favicon-32.png",
    "https://www.example.com/favicon.ico",
    "https://www.example.com/apple-touch-icon-precomposed.png",
  ]);
  assertEquals(candidates[0].source, "manifest");
  assertEquals(candidates[2].declaredSize, 180);
});

Deno.test("candidateIconURLs caps the list at eight", () => {
  const links = Array.from({ length: 12 }, (_, index) => `<link rel="icon" sizes="${16 * (index + 1)}x${16 * (index + 1)}" href="/i${index}.png">`).join("");
  assertEquals(candidateIconURLs(links, "https://www.example.com/").length, 8);
});

Deno.test("parseManifestIcons ignores malformed input", () => {
  assertEquals(parseManifestIcons("not json", "https://a.example/m.json"), []);
  assertEquals(parseManifestIcons(JSON.stringify({ icons: "nope" }), "https://a.example/m.json"), []);
  assertEquals(parseManifestIcons(JSON.stringify({ icons: [{ src: 7 }, { src: "https://10.0.0.1/x.png" }] }), "https://a.example/m.json"), []);
});

Deno.test("inspectImage reads PNG, JPEG, and ICO headers and flags animation", () => {
  assertEquals(inspectImage(pngBytes(180, 180)), { kind: "png", width: 180, height: 180, animated: false });
  assertEquals(inspectImage(pngBytes(64, 64, true))?.animated, true);
  assertEquals(inspectImage(jpegBytes(512, 384)), { kind: "jpeg", width: 512, height: 384, animated: false });
  const ico = icoBytes([bmpEntry, pngBytes(256, 256), pngBytes(48, 48)]);
  assertEquals(inspectImage(ico), { kind: "ico", width: 256, height: 256, animated: false });
  assertEquals(extractICOEntries(ico).length, 2);
  assertEquals(inspectImage(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0, 0])), null);
  assertEquals(inspectImage(new TextEncoder().encode("<svg xmlns='http://www.w3.org/2000/svg'/>")), null);
  assertEquals(inspectImage(icoBytes([bmpEntry])), null);
});

function decoded(url: string, bytes: Uint8Array): DecodedCandidate {
  const info = inspectImage(bytes);
  if (!info) throw new Error("test image is not decodable");
  return { url, bytes, info };
}

Deno.test("chooseMark prefers the largest square icon within limits", () => {
  const choice = chooseMark([
    decoded("https://a.example/wide.jpg", jpegBytes(1024, 300)),
    decoded("https://a.example/touch.png", pngBytes(180, 180)),
    decoded("https://a.example/big.png", pngBytes(512, 512)),
    decoded("https://a.example/small.png", pngBytes(32, 32)),
  ], []);
  assertEquals(choice.outcome, "fetched");
  if (choice.outcome === "fetched") assertEquals(choice.candidate.url, "https://a.example/big.png");
});

Deno.test("chooseMark reports no icon published when every icon is too small or animated", () => {
  const small = chooseMark([decoded("https://a.example/small.png", pngBytes(64, 64))], ["unreachable"]);
  assertEquals(small, { outcome: "no_icon_published", reason: "largest published icon is 64 px" });
  const animated = chooseMark([decoded("https://a.example/anim.png", pngBytes(256, 256, true))], []);
  assertEquals(animated, { outcome: "no_icon_published", reason: "only animated icons published" });
});

Deno.test("chooseMark reports the dominant failure when nothing decoded", () => {
  assertEquals(chooseMark([], ["wrong_kind", "unreachable", "unreachable"]), { outcome: "fetch_failed", reason: "unreachable" });
  assertEquals(chooseMark([], []), { outcome: "no_icon_published", reason: "no icon links found" });
});

Deno.test("chooseMark ignores oversized bytes", () => {
  const huge = { ...decoded("https://a.example/huge.png", pngBytes(1024, 1024)), bytes: new Uint8Array(1_048_577) };
  huge.bytes.set(pngBytes(1024, 1024));
  assertEquals(chooseMark([huge], []).outcome, "no_icon_published");
});

Deno.test("objectPath uses the company key, next version, and extension", () => {
  assertEquals(objectPath("shopify", 3, "png"), "shopify/3.png");
  assertEquals(objectPath("thomson-reuters", 1, "jpeg"), "thomson-reuters/1.jpg");
});

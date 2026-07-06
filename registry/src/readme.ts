// Extract a package's README from its published tarball.
//
// Packages are stored in R2 as `pkgs/<name>/<name>-<version>.tar.gz`: a
// gzip-compressed USTAR archive whose members are top-level relative paths
// (e.g. `README.md`, `nurl.toml`, `src/main.nu`). We gunzip with the
// platform `DecompressionStream` and walk the 512-byte tar blocks to find
// the README, without any third-party tar/gzip dependency.

const BLOCK = 512;

function readCStr(buf: Uint8Array, off: number, max: number): string {
  let end = off;
  const lim = Math.min(off + max, buf.length);
  while (end < lim && buf[end] !== 0) end++;
  return new TextDecoder().decode(buf.subarray(off, end));
}

function isZeroBlock(buf: Uint8Array, off: number): boolean {
  for (let i = off; i < off + BLOCK && i < buf.length; i++) if (buf[i] !== 0) return false;
  return true;
}

function isReadmeName(path: string): boolean {
  const base = path.split("/").pop()!.toLowerCase();
  return base === "readme.md" || base === "readme.markdown" || base === "readme";
}

// Walk an uncompressed tar image, returning the first regular-file member
// whose path satisfies `match`, as a view into `buf` (no copy). null if none.
function findInTar(
  buf: Uint8Array,
  match: (path: string) => boolean,
): { path: string; data: Uint8Array } | null {
  let pos = 0;
  while (pos + BLOCK <= buf.length) {
    if (isZeroBlock(buf, pos)) break; // end-of-archive marker
    const name = readCStr(buf, pos, 100);
    // Size: octal in the 12-byte field at offset 124 (may be space/NUL padded).
    const sizeRaw = readCStr(buf, pos + 124, 12).trim();
    const size = parseInt(sizeRaw.replace(/[^0-7]/g, "") || "0", 8);
    const typeflag = buf[pos + 156];
    const dataStart = pos + BLOCK;
    // typeflag '0' (0x30) or NUL (0) is a regular file.
    if ((typeflag === 0x30 || typeflag === 0) && name && match(name)) {
      return { path: name, data: buf.subarray(dataStart, dataStart + size) };
    }
    pos = dataStart + Math.ceil(size / BLOCK) * BLOCK;
  }
  return null;
}

// Find and decode the README in an uncompressed tar image. Returns the
// file's text, or null if the archive has no README member.
export function findReadmeInTar(buf: Uint8Array): string | null {
  const hit = findInTar(buf, isReadmeName);
  return hit ? new TextDecoder().decode(hit.data) : null;
}

// Normalise a README-relative path to a tar member path: drop a leading
// `./`, collapse repeated slashes, and reject traversal / absolute paths.
// Returns null if the path is unsafe.
export function normalizeRelPath(rel: string): string | null {
  const p = rel.replace(/^\.\//, "").replace(/\/{2,}/g, "/");
  if (p === "" || p.startsWith("/") || p.split("/").some((seg) => seg === "..")) return null;
  return p;
}

// Fetch + gunzip + extract the README for one published version. Returns
// null if the tarball is missing or carries no README. Never throws on a
// well-formed-but-readmeless archive; callers should still guard against
// network/decompression errors.
export async function extractReadme(
  bucket: R2Bucket,
  name: string,
  version: string,
): Promise<string | null> {
  const obj = await bucket.get(`pkgs/${name}/${name}-${version}.tar.gz`);
  if (!obj || !obj.body) return null;
  const ab = await new Response(obj.body.pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
  return findReadmeInTar(new Uint8Array(ab));
}

// Pull `[package].repository` out of the published tarball's nurl.toml.
// Returns the URL string, or null when absent/unreadable. Deliberately a
// tiny line-scan rather than a full TOML parser: we only need one scalar,
// and the registry must never break a package page over a manifest quirk.
export async function extractManifestRepository(
  bucket: R2Bucket,
  name: string,
  version: string,
): Promise<string | null> {
  const obj = await bucket.get(`pkgs/${name}/${name}-${version}.tar.gz`);
  if (!obj || !obj.body) return null;
  const ab = await new Response(obj.body.pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
  const hit = findInTar(new Uint8Array(ab), (p) => p.replace(/^\.\//, "") === "nurl.toml");
  if (!hit) return null;
  const toml = new TextDecoder().decode(hit.data);
  // `repository = "..."` under [package]; stop at the next table header so a
  // stray `repository` key in another section can't be mistaken for it.
  let inPackage = false;
  for (const raw of toml.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith("[")) { inPackage = line === "[package]"; continue; }
    if (!inPackage) continue;
    const m = line.match(/^repository\s*=\s*"([^"]*)"/);
    if (m) return m[1] || null;
  }
  return null;
}

// Fetch + gunzip a published tarball and return the bytes of the member at
// the exact relative path `rel` (e.g. `docs/demo.png`), or null if missing.
// Used to serve README-referenced assets (images) straight from the tarball.
export async function extractFile(
  bucket: R2Bucket,
  name: string,
  version: string,
  rel: string,
): Promise<Uint8Array | null> {
  const obj = await bucket.get(`pkgs/${name}/${name}-${version}.tar.gz`);
  if (!obj || !obj.body) return null;
  const ab = await new Response(obj.body.pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
  const hit = findInTar(new Uint8Array(ab), (p) => p.replace(/^\.\//, "") === rel);
  return hit ? hit.data : null;
}

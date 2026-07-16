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

export interface TarFileEntry { path: string; size: number; }

// List every regular file in an uncompressed tar image (path + size),
// in archive order. Unlike findInTar (which only ever matches root-level
// members, where the 100-byte name field always suffices), a full listing
// must reconstruct long paths: honour the USTAR `prefix` field and the
// GNU longname ('L') extension, and skip PAX/GNU metadata pseudo-entries.
export function listTarFiles(buf: Uint8Array): TarFileEntry[] {
  const out: TarFileEntry[] = [];
  let pos = 0;
  let gnuLongName: string | null = null;
  while (pos + BLOCK <= buf.length) {
    if (isZeroBlock(buf, pos)) break; // end-of-archive marker
    const sizeRaw = readCStr(buf, pos + 124, 12).trim();
    const size = parseInt(sizeRaw.replace(/[^0-7]/g, "") || "0", 8);
    const typeflag = buf[pos + 156];
    const dataStart = pos + BLOCK;
    if (typeflag === 0x4c) {
      // GNU 'L': the data block carries the NEXT entry's full path.
      gnuLongName = readCStr(buf, dataStart, size);
    } else if (typeflag === 0x30 || typeflag === 0) {
      const fromLongName = gnuLongName !== null;
      let path = gnuLongName ?? readCStr(buf, pos, 100);
      gnuLongName = null;
      // The USTAR prefix field only applies to names read from the 100-byte
      // header field, never to a GNU longname (which is already complete).
      if (!fromLongName && path && readCStr(buf, pos + 257, 6).startsWith("ustar")) {
        const prefix = readCStr(buf, pos + 345, 155);
        if (prefix) path = `${prefix}/${path}`;
      }
      path = path.replace(/^\.\//, "");
      if (path) out.push({ path, size });
    } else {
      // 'x'/'g' (PAX), 'K' (GNU longlink), directories, links: not files.
      gnuLongName = null;
    }
    pos = dataStart + Math.ceil(size / BLOCK) * BLOCK;
  }
  return out;
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

// Pull one `[package]` scalar out of the published tarball's nurl.toml.
// Returns the string, or null when absent/unreadable. Deliberately a
// tiny line-scan rather than a full TOML parser: we only need scalars,
// and the registry must never break over a manifest quirk. `key` values
// stop at the next table header so a stray key in another section can't
// be mistaken for it.
export async function extractManifestKey(
  bucket: R2Bucket,
  name: string,
  version: string,
  key: string,
): Promise<string | null> {
  const obj = await bucket.get(`pkgs/${name}/${name}-${version}.tar.gz`);
  if (!obj || !obj.body) return null;
  const ab = await new Response(obj.body.pipeThrough(new DecompressionStream("gzip"))).arrayBuffer();
  const hit = findInTar(new Uint8Array(ab), (p) => p.replace(/^\.\//, "") === "nurl.toml");
  if (!hit) return null;
  const toml = new TextDecoder().decode(hit.data);
  let inPackage = false;
  const re = new RegExp(`^${key}\\s*=\\s*"([^"]*)"`);
  for (const raw of toml.split(/\r?\n/)) {
    const line = raw.trim();
    if (line.startsWith("[")) { inPackage = line === "[package]"; continue; }
    if (!inPackage) continue;
    const m = line.match(re);
    if (m) return m[1] || null;
  }
  return null;
}

export function extractManifestRepository(
  bucket: R2Bucket,
  name: string,
  version: string,
): Promise<string | null> {
  return extractManifestKey(bucket, name, version, "repository");
}

// Description as recorded at publish: capped so a runaway manifest can't
// bloat search rows (yoloe-demo-style long descriptions stay useful).
export async function extractManifestDescription(
  bucket: R2Bucket,
  name: string,
  version: string,
): Promise<string> {
  const d = await extractManifestKey(bucket, name, version, "description");
  return (d ?? "").slice(0, 500);
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

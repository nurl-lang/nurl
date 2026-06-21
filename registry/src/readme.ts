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

// Find and decode the README in an uncompressed tar image. Returns the
// file's text, or null if the archive has no README member.
export function findReadmeInTar(buf: Uint8Array): string | null {
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
    if ((typeflag === 0x30 || typeflag === 0) && name && isReadmeName(name)) {
      return new TextDecoder().decode(buf.subarray(dataStart, dataStart + size));
    }
    pos = dataStart + Math.ceil(size / BLOCK) * BLOCK;
  }
  return null;
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

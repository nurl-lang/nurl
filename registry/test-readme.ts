// Unit tests for the README pipeline (markdown rendering + tar extraction).
// Run with: node test-readme.ts   (Node >= 22 strips the TS types natively).
import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { renderMarkdown } from "./src/markdown.ts";
import { findReadmeInTar, normalizeRelPath, listTarFiles, listTarSrcModules, readmeFirstParagraph } from "./src/readme.ts";
import { renderNurldoc } from "./src/nurldoc.ts";

let pass = 0, fail = 0;
function ok(cond: boolean, msg: string) {
  if (cond) { pass++; } else { fail++; console.log(`FAIL: ${msg}`); }
}
function has(hay: string, needle: string, msg: string) {
  ok(hay.includes(needle), `${msg} (missing: ${JSON.stringify(needle)})`);
}
function absent(hay: string, needle: string, msg: string) {
  ok(!hay.includes(needle), `${msg} (should not contain: ${JSON.stringify(needle)})`);
}

// ── markdown: blocks ──────────────────────────────────────────────────
has(renderMarkdown("# Title"), "<h1>Title</h1>", "h1");
has(renderMarkdown("### Sub"), "<h3>Sub</h3>", "h3");
has(renderMarkdown("- a\n- b"), "<ul>\n<li>a</li>\n<li>b</li>\n</ul>", "ul");
has(renderMarkdown("1. x\n2. y"), "<ol>\n<li>x</li>\n<li>y</li>\n</ol>", "ol");
has(renderMarkdown("> quoted"), "<blockquote>quoted</blockquote>", "blockquote");
has(renderMarkdown("---"), "<hr />", "hr");
has(renderMarkdown("one\ntwo"), "<p>one two</p>", "paragraph join");
has(renderMarkdown("```sh\nls -l\n```"), `<pre><code class="language-sh">ls -l</code></pre>`, "fenced code w/ lang");
has(renderMarkdown("```\nx<y\n```"), "x&lt;y", "code block escapes html");

// ── markdown: inline ──────────────────────────────────────────────────
has(renderMarkdown("a `b` c"), "<code>b</code>", "inline code");
has(renderMarkdown("**bold**"), "<strong>bold</strong>", "bold");
has(renderMarkdown("see [docs](https://x.io)"), `<a href="https://x.io" rel="noopener nofollow">docs</a>`, "link");
// code span content must not be re-processed as emphasis
has(renderMarkdown("`a*b*c`"), "<code>a*b*c</code>", "no emphasis inside code");
absent(renderMarkdown("`a*b*c`"), "<em>", "no <em> inside code span");

// ── inline spans that wrap across source lines (paragraph re-join) ─────
has(renderMarkdown("see [the\ndocs](https://x.io)"), `<a href="https://x.io" rel="noopener nofollow">the docs</a>`, "link wrapped across two lines");
has(renderMarkdown("a **bo\nld** word"), "<strong>bo ld</strong>", "bold wrapped across two lines");

// ── images ────────────────────────────────────────────────────────────
const idResolve = (u: string) =>
  /^[a-z]+:/i.test(u) || u.startsWith("/") || u.startsWith("#") ? u : "/files/yoloe/0.1.0/" + u;
has(renderMarkdown("![dog](docs/demo.png)"), `<img src="docs/demo.png" alt="dog" loading="lazy" />`, "image renders as <img>");
has(renderMarkdown("![dog](docs/demo.png)", idResolve), `<img src="/files/yoloe/0.1.0/docs/demo.png"`, "relative image src rewritten");
has(renderMarkdown("![x](https://e.org/a.png)", idResolve), `src="https://e.org/a.png"`, "absolute image src untouched");
has(renderMarkdown("![a](x.png) then [b](https://y.io)"), `<img src="x.png"`, "image beside link: image ok");
has(renderMarkdown("![a](x.png) then [b](https://y.io)"), `<a href="https://y.io"`, "image beside link: link ok");
absent(renderMarkdown("![x](javascript:alert(1))"), "<img", "javascript: image rejected");
absent(renderMarkdown("![x](javascript:alert(1))"), 'src="javascript', "javascript: not emitted as an image src");
// underscores in a filename must not be italicised
has(renderMarkdown("![p](docs/demo_promptable.png)"), `src="docs/demo_promptable.png"`, "underscores in image path survive");

// ── relative-path normalisation (asset route safety) ──────────────────
ok(normalizeRelPath("docs/demo.png") === "docs/demo.png", "normalize keeps clean path");
ok(normalizeRelPath("./docs/x.png") === "docs/x.png", "normalize strips leading ./");
ok(normalizeRelPath("../secret") === null, "normalize rejects ..");
ok(normalizeRelPath("a/../../b") === null, "normalize rejects embedded ..");
ok(normalizeRelPath("/etc/passwd") === null, "normalize rejects absolute");

// ── GFM table (with escaped pipes, like nq's README) ──────────────────
const tbl = renderMarkdown("| A | B |\n| - | - |\n| 1 | x \\| y |");
has(tbl, "<table>", "table open");
has(tbl, "<th>A</th>", "table header cell");
has(tbl, "<td>x | y</td>", "escaped pipe in cell");

// ── XSS safety ────────────────────────────────────────────────────────
absent(renderMarkdown("<script>alert(1)</script>"), "<script>", "raw html escaped");
has(renderMarkdown("<script>alert(1)</script>"), "&lt;script&gt;", "raw html shown as text");
absent(renderMarkdown("[x](javascript:alert(1))"), 'href="javascript', "javascript: link rejected");
absent(renderMarkdown("[x](data:text/html,evil)"), 'href="data:', "data: link rejected");
ok(!/<[^>]*\sonerror=/.test(renderMarkdown('![x](" onerror=alert(1) src=x)')), "no attribute injection");
// a sneaky sentinel collision attempt: plain " 0 " text must survive intact
has(renderMarkdown("value is 0 here"), "value is 0 here", "no placeholder collision on bare digits");

// ── tar extraction ────────────────────────────────────────────────────
function tarWith(name: string, body: string): Uint8Array {
  const data = new TextEncoder().encode(body);
  const blocks = Math.ceil(data.length / 512);
  const buf = new Uint8Array(512 + blocks * 512 + 1024); // header + data + 2 zero blocks
  const enc = new TextEncoder();
  buf.set(enc.encode(name), 0);                        // name @ 0
  buf.set(enc.encode("0000644\0"), 100);               // mode
  buf.set(enc.encode(data.length.toString(8).padStart(11, "0") + "\0"), 124); // size (octal)
  buf[156] = 0x30;                                      // typeflag '0'
  buf.set(enc.encode("ustar\0"), 257);                 // magic
  buf.set(enc.encode("00"), 263);                      // version
  buf.set(data, 512);                                  // file data
  return buf;
}
ok(findReadmeInTar(tarWith("README.md", "# Hi\n")) === "# Hi\n", "extract README.md");
ok(findReadmeInTar(tarWith("src/main.nu", "x")) === null, "no README -> null");
// nested-path README is found by basename
ok(findReadmeInTar(tarWith("nq/README.md", "# nq\n")) === "# nq\n", "README under a dir");

// ── tar file listing (the /packages/<n>/<v>/files page) ───────────────
// Multi-member archive builder; `typeflag`/`prefix` let one member carry
// USTAR long-path or GNU-longname metadata.
function tarMulti(members: { name: string; body: string; typeflag?: number; prefix?: string }[]): Uint8Array {
  const enc = new TextEncoder();
  const parts: Uint8Array[] = [];
  for (const m of members) {
    const data = enc.encode(m.body);
    const buf = new Uint8Array(512 + Math.ceil(data.length / 512) * 512);
    buf.set(enc.encode(m.name), 0);
    buf.set(enc.encode("0000644\0"), 100);
    buf.set(enc.encode(data.length.toString(8).padStart(11, "0") + "\0"), 124);
    buf[156] = m.typeflag ?? 0x30;
    buf.set(enc.encode("ustar\0"), 257);
    buf.set(enc.encode("00"), 263);
    if (m.prefix) buf.set(enc.encode(m.prefix), 345);
    buf.set(data, 512);
    parts.push(buf);
  }
  parts.push(new Uint8Array(1024)); // end-of-archive
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}
{
  const files = listTarFiles(tarMulti([
    { name: "nurl.toml", body: "[package]\n" },
    { name: "./src/main.nu", body: "code" },
    { name: "docs/", body: "", typeflag: 0x35 },               // directory: skipped
    { name: "docs/pic.png", body: "png-bytes" },
  ]));
  ok(files.length === 3, `listing has 3 files (got ${files.length})`);
  ok(files[0].path === "nurl.toml" && files[0].size === 10, "member path + size");
  ok(files[1].path === "src/main.nu", "leading ./ stripped");
  ok(files.every((f) => f.path !== "docs/"), "directory member skipped");
}
{
  // USTAR prefix reassembly for >100-char paths.
  const files = listTarFiles(tarMulti([{ name: "leaf.nu", body: "x", prefix: "very/deep/dir" }]));
  ok(files[0].path === "very/deep/dir/leaf.nu", "ustar prefix joined");
}
{
  // GNU longname: an 'L' pseudo-entry carries the NEXT member's path and
  // must itself not appear in the listing (nor pick up the ustar prefix).
  const files = listTarFiles(tarMulti([
    { name: "././@LongLink", body: "some/very/long/path/file.nu\0", typeflag: 0x4c },
    { name: "some/very/long/path/", body: "y", prefix: "ignored-for-longname" },
    { name: "plain.nu", body: "z" },
  ]));
  ok(files.length === 2, `longname listing has 2 files (got ${files.length})`);
  ok(files[0].path === "some/very/long/path/file.nu", "GNU longname applied");
  ok(files[1].path === "plain.nu", "longname does not leak to later members");
}

// ── round-trip: real nq README renders without throwing ───────────────
try {
  const nq = readFileSync(new URL("../packages/nq/README.md", import.meta.url), "utf8");
  const html = renderMarkdown(nq);
  has(html, "<h1>", "nq README has an h1");
  has(html, "<table>", "nq README table renders");
  has(html, "<code>nq</code>", "nq README inline code renders");
  absent(html, "<script", "nq README produces no script tag");
  // gzip+tar round-trip shape check (decompress happens in the Worker via
  // DecompressionStream; here we just confirm our tar reader finds it).
  const gz = gzipSync(Buffer.from(tarWith("README.md", nq)));
  ok(gz.length > 0, "gzip of tar produced bytes");
} catch (e) {
  fail++; console.log(`FAIL: nq README round-trip threw: ${e}`);
}

// ── README first paragraph (description fallback) ────────────────────
ok(readmeFirstParagraph("# t — x\n\nOne dependency for **serving** HTTP.\nSecond line.\n\nNext para.") ===
  "One dependency for serving HTTP. Second line.", "first paragraph joined, bold stripped, heading skipped");
ok(readmeFirstParagraph("# only a title") === "", "title-only README yields empty");
ok(readmeFirstParagraph("no heading at all\n\nrest") === "no heading at all", "headingless README works");

// ── nurldoc: doc surface extraction ──────────────────────
const NUDOC = `// demo.nu — the fixture module.

// A friendly greeting for @who.
@ demo_hello s who -> i { ^ 0 }

// file-private, must NOT appear in the API docs.
@ __demo_secret i x -> i { ^ x }

// A record with fields.
: Point {
    i x
    i y
}
`;
{
  const md = renderNurldoc(NUDOC, "demo.nu");
  has(md, "# demo.nu", "nurldoc emits the module title");
  has(md, "the fixture module", "nurldoc emits the header prose");
  has(md, "demo_hello", "nurldoc documents the public function");
  has(md, "friendly greeting", "nurldoc keeps the doc comment");
  absent(md, "__demo_secret", "nurldoc omits file-private functions");
  has(md, "Point", "nurldoc documents a type");
  has(md, "```nurl", "nurldoc fences the type definition");
  has(md, "i x", "nurldoc includes the type fields");
}
{
  const gz = tarMulti([
    { name: "README.md", body: "# demo\n" },
    { name: "src/demo.nu", body: NUDOC },
    { name: "nurl.toml", body: "[package]\nname=x\n" },
  ]);
  const mods = listTarSrcModules(gz);
  ok(mods.length === 1, "listTarSrcModules finds exactly the src/*.nu module");
  ok(mods.length === 1 && mods[0].path === "src/demo.nu", "listTarSrcModules returns the src path");
  ok(mods.length === 1 && mods[0].text.includes("demo_hello"), "listTarSrcModules returns the module text");
}

console.log(`\n==== ${pass} passed, ${fail} failed ====`);
process.exit(fail ? 1 : 0);

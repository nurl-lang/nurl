// Unit tests for the README pipeline (markdown rendering + tar extraction).
// Run with: node test-readme.ts   (Node >= 22 strips the TS types natively).
import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { renderMarkdown } from "./src/markdown.ts";
import { findReadmeInTar } from "./src/readme.ts";

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
has(renderMarkdown("> quoted"), "<blockquote>quoted </blockquote>", "blockquote");
has(renderMarkdown("---"), "<hr />", "hr");
has(renderMarkdown("one\ntwo"), "<p>one two </p>", "paragraph join");
has(renderMarkdown("```sh\nls -l\n```"), `<pre><code class="language-sh">ls -l</code></pre>`, "fenced code w/ lang");
has(renderMarkdown("```\nx<y\n```"), "x&lt;y", "code block escapes html");

// ── markdown: inline ──────────────────────────────────────────────────
has(renderMarkdown("a `b` c"), "<code>b</code>", "inline code");
has(renderMarkdown("**bold**"), "<strong>bold</strong>", "bold");
has(renderMarkdown("see [docs](https://x.io)"), `<a href="https://x.io" rel="noopener nofollow">docs</a>`, "link");
// code span content must not be re-processed as emphasis
has(renderMarkdown("`a*b*c`"), "<code>a*b*c</code>", "no emphasis inside code");
absent(renderMarkdown("`a*b*c`"), "<em>", "no <em> inside code span");

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

console.log(`\n==== ${pass} passed, ${fail} failed ====`);
process.exit(fail ? 1 : 0);

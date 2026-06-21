// A small, dependency-free, XSS-safe Markdown -> HTML renderer.
//
// Scope: the subset that package READMEs actually use -- ATX headings,
// fenced code blocks, blockquotes, unordered/ordered lists, GFM tables,
// horizontal rules, paragraphs, and inline code / bold / italic / links.
// It is NOT a full CommonMark implementation; it is deliberately tiny and
// predictable.
//
// Security: this renders untrusted input (any package author's README), so
// every run of literal text is HTML-escaped, raw HTML in the source is
// never passed through, and link targets are restricted to a safe scheme
// allowlist (no javascript: / data:).

function esc(s: string): string {
  return s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]!));
}

// Validate a link target. `url` arrives already HTML-escaped, so attribute
// injection is impossible here; we only need to reject dangerous schemes.
// Allowed: http(s), mailto, and same-document / relative links.
function safeUrl(url: string): string | null {
  const u = url.trim();
  if (u === "") return null;
  // A scheme is letters/digits/+/-/. followed by ':'. If there is no scheme
  // before the path, it is a relative URL -- allow it.
  const scheme = u.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):/);
  if (scheme) {
    const s = scheme[1].toLowerCase();
    if (s !== "http" && s !== "https" && s !== "mailto") return null;
  }
  return u;
}

// A Private-Use-Area codepoint that cannot appear in escaped README text,
// used as a collision-free placeholder for already-rendered code spans.
const SENTINEL = String.fromCharCode(0xe000);

// Inline formatting for a single run of text.
function inline(raw: string): string {
  let s = esc(raw);

  // Pull code spans out first so their contents are never re-processed by
  // the emphasis / link passes below.
  const codes: string[] = [];
  s = s.replace(/`([^`]+)`/g, (_m, c: string) => {
    codes.push(`<code>${c}</code>`);
    return `${SENTINEL}${codes.length - 1}${SENTINEL}`;
  });

  s = s.replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/__([^_\n]+)__/g, "<strong>$1</strong>");
  s = s.replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<em>$2</em>");
  s = s.replace(/(^|[^_\w])_([^_\n]+)_/g, "$1<em>$2</em>");

  s = s.replace(/\[([^\]]*)\]\(([^)\s]+)\)/g, (_m, text: string, url: string) => {
    const safe = safeUrl(url);
    return safe
      ? `<a href="${safe}" rel="noopener nofollow">${text}</a>`
      : `[${text}](${url})`;
  });

  const restore = new RegExp(`${SENTINEL}(\\d+)${SENTINEL}`, "g");
  s = s.replace(restore, (_m, n: string) => codes[+n]);
  return s;
}

// ── GFM table helpers ─────────────────────────────────────────────────

// Split a table row on unescaped `|`, dropping the optional leading/
// trailing pipe, and unescape `\|` inside each cell.
function splitRow(line: string): string[] {
  let t = line.trim();
  t = t.replace(/^\|/, "").replace(/\|$/, "");
  return t.split(/(?<!\\)\|/).map((c) => c.replace(/\\\|/g, "|").trim());
}

// A delimiter row is `---|:--:|--` style: each cell only `-`, `:`, spaces,
// with at least one `-`.
function isDelimRow(line: string): boolean {
  const t = line.trim().replace(/^\|/, "").replace(/\|$/, "");
  if (!t.includes("-")) return false;
  return t.split(/(?<!\\)\|/).every((c) => /^\s*:?-+:?\s*$/.test(c));
}

function renderTable(lines: string[], start: number, out: string[]): number {
  out.push("<table>\n<thead>\n<tr>");
  for (const c of splitRow(lines[start])) out.push(`<th>${inline(c)}</th>`);
  out.push("</tr>\n</thead>\n<tbody>\n");
  let i = start + 2; // skip header + delimiter row
  while (i < lines.length && lines[i].includes("|") && lines[i].trim() !== "") {
    out.push("<tr>");
    for (const c of splitRow(lines[i])) out.push(`<td>${inline(c)}</td>`);
    out.push("</tr>\n");
    i++;
  }
  out.push("</tbody>\n</table>\n");
  return i - 1; // caller's loop does i++
}

// ── Block renderer ────────────────────────────────────────────────────

type Block = "p" | "ul" | "ol" | "bq" | null;

export function renderMarkdown(src: string): string {
  const lines = src.replace(/\r\n?/g, "\n").split("\n");
  const out: string[] = [];
  let open: Block = null;

  const close = () => {
    if (open === "p") out.push("</p>\n");
    else if (open === "ul") out.push("</ul>\n");
    else if (open === "ol") out.push("</ol>\n");
    else if (open === "bq") out.push("</blockquote>\n");
    open = null;
  };
  const ensure = (b: Block, openTag: string) => {
    if (open !== b) { close(); out.push(openTag); open = b; }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Fenced code block.
    const fence = line.match(/^\s*```(.*)$/);
    if (fence) {
      close();
      const lang = fence[1].trim();
      out.push(`<pre><code${lang ? ` class="language-${esc(lang)}"` : ""}>`);
      i++;
      const buf: string[] = [];
      while (i < lines.length && !/^\s*```/.test(lines[i])) { buf.push(esc(lines[i])); i++; }
      out.push(buf.join("\n"));
      out.push("</code></pre>\n");
      continue; // i sits on the closing fence (or past end); loop ++ advances
    }

    if (line.trim() === "") { close(); continue; }

    // ATX heading.
    const h = line.match(/^(#{1,6})\s+(.*?)\s*#*\s*$/);
    if (h) { close(); const n = h[1].length; out.push(`<h${n}>${inline(h[2])}</h${n}>\n`); continue; }

    // Horizontal rule.
    if (/^ {0,3}([-*_])\s*(\1\s*){2,}$/.test(line)) { close(); out.push("<hr />\n"); continue; }

    // Blockquote.
    const bq = line.match(/^>\s?(.*)$/);
    if (bq) { ensure("bq", "<blockquote>"); out.push(inline(bq[1]) + " "); continue; }

    // GFM table (current line has a pipe, next line is a delimiter row).
    if (line.includes("|") && i + 1 < lines.length && isDelimRow(lines[i + 1])) {
      close();
      i = renderTable(lines, i, out);
      continue;
    }

    // Unordered list item.
    const ul = line.match(/^\s*[-*+]\s+(.*)$/);
    if (ul) { ensure("ul", "<ul>\n"); out.push(`<li>${inline(ul[1])}</li>\n`); continue; }

    // Ordered list item.
    const ol = line.match(/^\s*\d+\.\s+(.*)$/);
    if (ol) { ensure("ol", "<ol>\n"); out.push(`<li>${inline(ol[1])}</li>\n`); continue; }

    // Paragraph (consecutive plain lines join with a space).
    ensure("p", "<p>");
    out.push(inline(line.trim()) + " ");
  }

  close();
  return out.join("");
}

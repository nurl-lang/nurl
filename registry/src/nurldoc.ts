// Render a NURL module's doc surface to Markdown — a faithful TypeScript
// port of stdlib/ext/nurldoc.nu, so the Worker's /api pages match what the
// `nurldoc` CLI (and the pure-NURL registry) produce.
//
// The discipline it reads: a `//` module-header block at the top, top-level
// declarations, and `//` doc comments immediately above them. It emits the
// header block as prose, then each top-level declaration's signature (the
// line up to its `{` body, for functions; the full `{ … }` definition for
// types/enums) with any preceding doc comment. Brace depth is tracked so
// `:` locals inside function bodies are never picked up, and `__`-prefixed
// (file-private) functions are excluded.

function skipWs(s: string): number {
  let i = 0;
  while (i < s.length && (s[i] === " " || s[i] === "\t")) i++;
  return i;
}

// Net brace delta of one line, counting {/} only in code (outside a `//`
// comment and outside backtick strings).
function braceDelta(line: string): number {
  let depth = 0;
  let inStr = false;
  for (let k = 0; k < line.length; k++) {
    const c = line[k];
    if (inStr) {
      if (c === "`") inStr = false;
    } else if (c === "`") {
      inStr = true;
    } else if (c === "/" && line[k + 1] === "/") {
      break; // rest of line is a comment
    } else if (c === "{") {
      depth++;
    } else if (c === "}") {
      depth--;
    }
  }
  return depth;
}

// The first declaration char after an optional leading `pub `, or "".
function declChar(rest: string): string {
  let r = rest;
  if (r.startsWith("pub ")) r = r.slice(4).replace(/^[ \t]+/, "");
  return r.length ? r[0] : "";
}

// The `//` comment body (leading `//` + one optional space stripped).
function commentBody(line: string, sp: number): string {
  let k = sp + 2;
  if (line[k] === " ") k++;
  return line.slice(k);
}

// The declaration signature from `sp`. Functions/multi-line type decls cut
// at the `{` body open; single-line decls keep the whole line. Trailing
// whitespace trimmed.
function signature(line: string, sp: number, cutBrace: boolean): string {
  let brace = line.length;
  if (cutBrace) {
    let inStr = false;
    for (let k = sp; k < line.length; k++) {
      const c = line[k];
      if (inStr) {
        if (c === "`") inStr = false;
      } else if (c === "`") {
        inStr = true;
      } else if (c === "{") {
        brace = k;
        break;
      }
    }
  }
  return line.slice(sp, brace).replace(/[ \t\n]+$/, "");
}

// Is this function declaration file-private (a `__`-prefixed name)? The
// compiler scopes such functions per-file, so documenting them is noise.
function fnIsPrivate(line: string, sp: number): boolean {
  let s = line.slice(sp);
  if (s.startsWith("pub ")) s = s.slice(4).replace(/^[ \t]+/, "");
  if (s.startsWith("&")) {
    // FFI form: & `lib` @ name … — advance past the backtick-quoted lib.
    s = s.slice(1).replace(/^[ \t]+/, "");
    if (s.startsWith("`")) {
      const e = s.indexOf("`", 1);
      if (e >= 0) s = s.slice(e + 1).replace(/^[ \t]+/, "");
    }
  }
  if (!s.startsWith("@")) return false;
  s = s.slice(1).replace(/^[ \t]+/, "");
  return s.startsWith("__");
}

export function renderNurldoc(content: string, title: string): string {
  const lines = content.split("\n");
  let header = ""; // top `//` block (module prose)
  let pending: string[] = []; // doc comment(s) above the next decl
  let body = ""; // accumulated "## API" entries
  let depth = 0;
  let headerDone = false;
  let anyDecl = false;
  let inType = false;
  let typeProse: string[] = [];

  for (const line of lines) {
    const sp = skipWs(line);
    const blank = sp === line.length;
    const isComment = !blank && line.slice(sp).startsWith("//");

    if (depth === 0) {
      if (isComment) {
        if (headerDone) pending.push(commentBody(line, sp));
        else header += commentBody(line, sp) + "\n";
      } else if (blank) {
        // a blank line ends a pending doc block (and the header)
        headerDone = true;
        pending = [];
      } else {
        headerDone = true;
        const dc = declChar(line.slice(sp));
        if (dc === "@" || dc === "&" || dc === "%" || dc === ":") {
          const isFn = dc === "@" || dc === "&";
          if (isFn && fnIsPrivate(line, sp)) {
            // file-private: not API
          } else {
            anyDecl = true;
            const bd = braceDelta(line);
            const typeBlock = !isFn && bd > 0;
            body += "### `" + signature(line, sp, isFn || typeBlock) + "`\n\n";
            if (typeBlock) {
              // open the fenced full definition; prose waits for the close
              inType = true;
              typeProse = pending.slice();
              body += "```nurl\n" + line + "\n";
            } else if (pending.length) {
              body += pending.join("\n") + "\n\n";
            }
          }
        }
        pending = [];
      }
    } else if (inType) {
      body += line + "\n";
    }

    depth += braceDelta(line);
    if (depth < 0) depth = 0;
    if (inType && depth === 0) {
      body += "```\n\n";
      if (typeProse.length) body += typeProse.join("\n") + "\n\n";
      inType = false;
    }
  }

  let out = `# ${title}\n\n`;
  if (header.length) out += header + "\n";
  if (anyDecl) out += "## API\n\n" + body;
  return out;
}

# NURL — Canonical Source Format (`nurlfmt`)

This page specifies the **deterministic source-level formatting**
that `nurlfmt` produces. The rules are opinionated and
non-configurable: there is one canonical shape per source, full stop.
Same ethos as `gofmt` / `zig fmt` / `rustfmt --edition=...`.

This is the dual of the byte-identical-IR bootstrap acceptance
criterion: `nurlc(x) == nurlc(nurlc-roundtrip(x))` checks that the
compiler is deterministic; `nurlfmt(nurlfmt(x)) == nurlfmt(x)`
checks that the formatter is. The two together pin the project's
output stack from source through IR.

The rules are designed to:

* **be cheap to derive from a token stream** — NURL's regular prefix
  grammar has no precedence and no implicit grouping, so a
  brace-/paren-/bracket-aware token walker can produce the canonical
  form without building a CST,
* **minimise gratuitous diffs** — preserve user line structure where
  the line break carries information (block bodies, top-level
  declarations, multi-arm matches) and collapse it where it does not
  (intra-expression alignment whitespace, blank-run collapsing),
* **be friendly to LLM generation** — one canonical output shape per
  semantically-equivalent program means models can target a single
  layout, and reviewers can run `nurlfmt --check` to gate diff noise.

---

## 1. Indentation

* **4 spaces per nesting level.** No tabs. No exceptions.
* A nesting level is opened by `{` and closed by `}`. Parentheses
  `(...)` and brackets `[...]` do **not** add indent levels (call
  arguments and slice/type-list bodies stay on one line by default,
  see §6 for the multi-line rule).
* Top-level declarations sit at indent 0.
* The closing `}` aligns with the column of the construct that
  opened the matching `{`.

```nurl
@ fizzbuzz i n → v {
    : ~ i i 1
    ~ <= i n {
        : b div3 == 0 % i 3
        : b div5 == 0 % i 5
        ? & div3 div5
            { ( nurl_print `FizzBuzz\n` ) }
            ? div3
                { ( nurl_print `Fizz\n` ) }
                { ( nurl_print `\n` ) }
        = i + i 1
    }
}
```

## 2. Inter-token spacing

* **Exactly one ASCII space between adjacent tokens.** No tabs, no
  multi-space alignment, no zero-width separation.
* The lexer's `::` glue inside a single IDENT (`json::parse` →
  `json__parse`) is preserved verbatim — `::` is part of the token,
  not a separator.
* No space between a unary sigil and its single operand only when the
  sigil is part of the token itself (e.g. negative literals `-7`,
  `-3.14` lex as one INT/FLOAT token; the `-` carries no space). All
  prefix operators that are their own token (`!`, `^`, `~`, `\`, `.`,
  `#`, `?`, `??`, `=`, `:`, `;`, `Z`) take one space before their
  next token.

## 3. Spaces inside delimiters

| Form                | Canonical shape         |
|---------------------|-------------------------|
| Call                | `( fn arg arg )`        |
| Empty call          | `( fn )`                |
| Slice literal       | `[ T \| 1 2 3 ]`        |
| Empty slice         | `[ T \| ]`              |
| Generic instantiation (type pos) | `( Vec i )` |
| Type-arg list (call site) | `( id [ i ] 42 )` |
| Type-param list (decl)    | `[ T ]` / `[ A B ]` |
| Aggregate / enum constructor | `@ Rect { 3 7 }` |
| Block as expression | `{ stmt stmt }` (single-line OK if short) |

The rule is mechanical: the **opening delimiter** is followed by
one space, the **closing delimiter** is preceded by one space, **but
both sides collapse to nothing when the inside is empty**: `( fn )`
keeps the spaces because the inside is non-empty (the `fn` name);
`{}` keeps no spaces because the inside is empty (legal as a no-op
arm in a ternary, see fizzbuzz).

Exception: the `(@ R P*)` function-type form keeps the canonical
spacing `(@ i i)` — the `(@` digraph has no internal space because
the lexer treats them as the function-type opener. The rest of the
form is normal `( @ R P* )` only at the source level if the user
writes it that way; the `(@` form is preferred and is what nurlfmt
emits.

## 4. Newlines and statements

* Inside a `{ ... }` block, **each statement starts on its own
  line.** A statement is a `:` let, `=` set, `;` defer, `~` loop,
  `~ IDENT ...` foreach, or a side-effecting expression.
* Match arms (`?? expr { ... }`) follow the same rule: each arm on
  its own line.
* The opening `{` stays on the same line as the construct that owns
  it.
* The closing `}` is on its own line, aligned with the opener.
* Expressions never wrap automatically — long expressions stay on
  one line. The user is free to break a long expression across lines
  with their own newlines + indent, and nurlfmt **preserves
  user-introduced newlines inside a single expression** (see §7).

## 5. Blank lines

* **Top-level declarations** (`$`, `&`, `%`, `@`, `:` decl) are
  separated by **exactly one blank line**. Multiple consecutive
  user-introduced blank lines collapse to one.
* **Inside a block**, blank lines between statements are preserved
  if the user wrote one, but multiple consecutive blank lines
  collapse to one.
* No blank line immediately after `{` or immediately before `}`.
* No trailing whitespace on any line.
* The file ends with **exactly one** `\n` (one final newline, no
  trailing blank line).

## 6. Long lines and forced wrapping

`nurlfmt` v1 does **not** automatically wrap long lines. Rationale:

1. Prefix-notation expressions have no precedence cliffs that make
   one wrap "more right" than another.
2. NURL's call form `( fn arg arg )` already gives the user a
   natural wrap point (each arg on its own indented line) when they
   want it; preserving that decision avoids fighting the user.
3. Statement-level wrapping is rarely needed because the language is
   token-dense — even long-looking forms fit comfortably on 100
   columns once stripped of decorative whitespace.

A future v2 may add a soft column budget (probably 100), but v1's
contract is "preserve the user's expression-internal newlines if
present, otherwise keep the expression on one line."

## 7. User-introduced newlines inside expressions

If the user breaks an expression across lines (commonly inside a
ternary cascade or a multi-arg call), `nurlfmt` preserves those
line breaks but **re-indents the continuation to the surrounding
block's indent level** — it does not bump them by an extra level
for cascading-construct alignment.

```nurl
// Before
? & div3 div5 { a } ? div3 { b } { c }
```

```nurl
// After (formatter keeps the user's three lines but indents all
// three at the surrounding block's level — no cascading bump):
? & div3 div5
{ a }
? div3
{ b }
{ c }
```

This is intentionally simple in v1: indent is purely a function of
brace depth (§1). A cascading-construct heuristic that walks back
to the construct opener and bumps continuation lines by one extra
level is on the v2 backlog (see ROADMAP §3). It is the single
biggest visible diff between v1 nurlfmt output and the
conventionally hand-formatted source in `examples/` and `stdlib/`.
The diff is **layout-only**: the formatted source still compiles to
the same LLVM IR as the original, which the round-trip test in
work-list item 6 enforces.

## 8. Comments

Two recognised forms (grammar §LEXICAL):

* `// ... \n` — line comment, runs to end of line.
* No block comments (deliberate — one comment shape, less mental
  load).

Comment placement is **preserved exactly** in two flavours:

* **Trailing comment** (token + comment on same line): kept on the
  same line, separated from the preceding token by **two spaces**.
  ```nurl
  : i n 0  // counter
  ```
* **Leading comment** (comment alone on a line): kept on its own
  line at the same indent as the next non-comment token.
  ```nurl
  // Boot-time setup. Plants index.html on first run.
  @ setup_public_dir → v {
      ...
  }
  ```

A comment that the user placed *between* statements on its own line
stays on its own line. A comment whose original position is on a
line by itself is never collapsed onto an adjacent statement.

`//` and the comment text are preserved verbatim — internal whitespace
and any trailing spaces in the comment body are kept as written.

## 9. String literals

Backtick-delimited strings are emitted verbatim, including their
escape sequences (`\n`, `\t`, `\r`, `\\`, and any pass-through
`\X`). The `STR` token is opaque to the formatter — it is never
re-tokenised.

## 10. Negative numeric literals

A `-` immediately followed by a digit (no intervening whitespace)
is a single INT/FLOAT token in the grammar. `nurlfmt` emits it the
same way: `-7`, `-3.14`. Binary minus stays separated: `- a b` for
`a - b`.

## 11. Idempotence

`nurlfmt(nurlfmt(x)) == nurlfmt(x)` byte-for-byte for every legal
NURL source `x`. This is enforced by
`compiler/tests/nurlfmt_idempotent.sh`, which runs the formatter
twice over the entire `stdlib/`, `examples/`, `compiler/tests/`, and
`compiler/nurlc.nu` source tree and diffs the second pass against
the first.

A second test confirms semantic equivalence: every formatted file
must compile to the **same LLVM IR** as its original via `nurlc`.
This catches any case where the formatter changes a token's
context (e.g. by losing or inserting a space that affects lexing
rules — the `< <` vs `<<` boundary, the negative-literal-vs-binary-
minus boundary).

---

## Worked example

### Before

```nurl
// rough indentation, mixed widths, decorative columns
@ inc_counter Counter c → Counter {
   = . c n   + . c n 1
       ^ c
}

@ main → i {
  : Counter c @ Counter { 0 10 }
  = c (inc_counter c)


  = c ( inc_counter   c )
  ^ . c n
}
```

### After

```nurl
// rough indentation, mixed widths, decorative columns
@ inc_counter Counter c → Counter {
    = . c n + . c n 1
    ^ c
}

@ main → i {
    : Counter c @ Counter { 0 10 }
    = c ( inc_counter c )

    = c ( inc_counter c )
    ^ . c n
}
```

Concretely: indent normalised to 4 spaces, decorative inner spacing
collapsed, `( inc_counter c )` re-spaced canonically (`( fn ... )`
keeps one space inside), top-level declarations separated by exactly
one blank line, and the duplicate blank line between the two `= c`
statements inside `main` collapsed to one.

---

## CLI

```
nurlfmt [OPTIONS] [FILE...]

Options:
    --check         Exit 0 if every FILE is already canonical, exit 1
                    otherwise. Print the names of files that need
                    reformatting to stderr. Suitable for CI.
    --write         Reformat each FILE in place. Without this flag the
                    formatted source is written to stdout.
    --stdin         Read a single source from stdin and write the
                    formatted result to stdout. Cannot be combined
                    with FILE arguments.

With no FILE and no --stdin, reads stdin → writes stdout (same as
--stdin).
```

Exit codes:

* `0` — success (formatted output written, or `--check` passed).
* `1` — `--check` found at least one non-canonical file.
* `2` — usage error or I/O error.

## Non-goals (v1)

* No configuration. Layout is fixed.
* No automatic line wrapping (§6).
* No comment reflowing.
* No alignment of `:`-typed columns or `=`-targets across lines.
* No support for editor-driven partial-file formatting (LSP-grade
  range formatting is a v2 concern).

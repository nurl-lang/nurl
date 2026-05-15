// tools/nurlfmt/pretty.nu — token-stream pretty-printer.
//
// Walks a Vec[FmtTok] (produced by tools/nurlfmt/tokenize.nu) and
// emits the canonical layout described in docs/FORMAT.md.
//
// Algorithm
// ---------
//
// Track three pieces of state while walking left-to-right:
//
//   bd   — brace depth (`{` opens, `}` closes). Indent = bd * 4.
//   pd   — paren+bracket depth (`(` `[` open, `)` `]` close). Used
//          only to decide whether we are inside a delimited form
//          (call args, slice literal, type-paren). When pd > 0 a
//          user-introduced newline is treated like any other token
//          break and the continuation is re-indented one extra
//          level above the surrounding `{`-depth.
//   at_line_start — true at the start of every emitted line, until
//          the first non-whitespace byte goes out. Drives the
//          indent prefix.
//
// For each token the inter-token spacing is decided by:
//
//   * nl_before == 0 → one space separator, with two exceptions:
//       - the previous token was an opener (`(`,`[`,`{`) immediately
//         followed by its matching closer ⇒ no inner space
//         (`()`, `[]`, `{}`),
//       - the comment-after-token rule emits TWO spaces before a
//         trailing `//` comment per docs/FORMAT.md §8.
//
//   * nl_before == 1 → newline + indent.
//
//   * nl_before >= 2 → blank line + indent (clamped at one blank).
//
// Top-level boundary (bd == 0): a non-comment, non-EOF token after
// the first emitted token always gets a blank line above it,
// regardless of nl_before. This is the "exactly one blank line
// between top-level declarations" rule.
//
// The formatter never inserts user-facing line breaks; it only
// preserves and re-indents the ones the user wrote, plus the
// inter-decl blank line, plus the trailing newline at EOF.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `tools/nurlfmt/tokenize.nu`

// ── Output buffer ─────────────────────────────────────────────
// We accumulate the formatted output into a String (Vec[u]-backed
// growable buffer) and return its `string_data` view at the end.

// Append `n` spaces to `out`.
@ __pp_indent String out i n → v {
    : ~ i k 0
    ~ < k n {
        ( string_push_char out 32 )
        = k + k 1
    }
}

// Token-text predicate helpers. Operate on raw `s` pointers; the
// FmtTok's `text` field is exactly the source slice so byte-level
// equality is correct.

@ __pp_text_eq s a s b → b {
    ^ != 0 ( nurl_str_eq a b )
}

// Is this token an opener that pairs immediately with the next
// token to form an empty `()` / `[]` / `{}` form? The caller has
// already verified the next token is on the same line; this
// predicate only checks the bracket-pair shape.
@ __pp_is_empty_pair s prev_text s next_text → b {
    ? & ( __pp_text_eq prev_text `(` ) ( __pp_text_eq next_text `)` ) { ^ T } {}
    ? & ( __pp_text_eq prev_text `[` ) ( __pp_text_eq next_text `]` ) { ^ T } {}
    ? & ( __pp_text_eq prev_text `{` ) ( __pp_text_eq next_text `}` ) { ^ T } {}
    ^ F
}

// True iff `t` is the first token of a top-level declaration shape.
// At depth 0 these tokens start a new decl and get a blank line
// above (`@` fn, `$` import, `&` ffi, `%` trait/impl, `:` struct/
// enum/const).
@ __pp_starts_top_decl s text → b {
    ? ( __pp_text_eq text `@` ) { ^ T } {}
    ? ( __pp_text_eq text `$` ) { ^ T } {}
    ? ( __pp_text_eq text `&` ) { ^ T } {}
    ? ( __pp_text_eq text `%` ) { ^ T } {}
    ? ( __pp_text_eq text `:` ) { ^ T } {}
    // Grammar v2.0 visibility prefix. Treated as a top-decl starter so
    // it gets the inter-decl blank line above it, and the following
    // sigil (`@`/`:`/`&`/`%`) suppresses its own blank line because
    // `pub` has already claimed the slot.
    ? ( __pp_text_eq text `pub` ) { ^ T } {}
    ^ F
}

// ── Main driver ────────────────────────────────────────────────
//
// pretty_print: walk the token stream and produce the canonical
// source layout as an owned String. The caller views the bytes
// via `string_data` for the lifetime of the returned binding.

@ pretty_print ( Vec FmtTok ) toks → String {
    : String out ( string_with_cap 4096 )

    : i n ( vec_len [FmtTok] toks )
    : ~ i bd 0  // brace depth (drives indent)
    : ~ i pd 0  // paren+bracket depth (informational)
    : ~ i bk 0  // bracket depth `[...]` — content tight-spaced by rule
    : ~ b emitted_any F
    : ~ s prev_text ``
    : ~ i prev_kind 0
    : ~ s prev_top_starter ``  // first-token text of the most recent depth-0 decl
    : ~ b last_line_open T  // true → current line has no content yet
    // type-prefix tightness: when `*T` / `?T` / `[T` appears as a TYPE,
    // the type-prefix sigil glues to the following type identifier with
    // no space between them. We approximate "is in type context" by
    // tracking the previous token: anything coming right after a
    // type-context-trigger (`:`, `→`, `(@` handled as `(` + `@`, `#`,
    // `Z`, `@` aggregate, or another type-prefix sigil) is considered
    // type position.
    : ~ b prev_is_type_prefix F  // prev token was *,?,[,! in type pos
    : ~ b prev_was_pub F  // prev token at bd=0/pd=0 was the `pub` keyword

    : ~ i idx 0
    ~ < idx n {
        ?? ( vec_get [FmtTok] toks idx ) {
            T t → {
                : i kind . t kind
                : s text . t text
                : i nl . t nl_before

                ? == kind TT_FMT_EOF {
                    // Ensure exactly one trailing newline at end of
                    // file: if we already finished a line, do
                    // nothing; otherwise emit `\n`. Either way the
                    // loop's terminating condition handles the rest.
                    ? & emitted_any ! last_line_open {
                        ( string_push_char out 10 )
                    } {}
                } {

                    // Decide how this token relates to its predecessor.
                    : ~ i pre_newlines 0
                    : ~ b pre_two_space F

                    ? ! emitted_any {
                        // First token in the file. Drop any leading
                        // blank lines but keep the token at column 0.
                        = pre_newlines 0
                    } {
                        // Top-level decl boundary forces a blank line
                        // unless the preceding token was a comment that
                        // belongs to this decl (its nl_before == 1 path
                        // already keeps the comment glued to the next
                        // token at the same indent), OR the boundary is
                        // between two consecutive `$` imports (which
                        // stay packed by convention).
                        // Grammar v2.0: `pub` glues to its decl-starter.
                        // When the previous top-level token was `pub`,
                        // the following `@`/`:`/`&`/`%`/`$` is part of
                        // the same logical decl, so we suppress the
                        // top-boundary blank line that would normally
                        // appear here. The user's original nl_before is
                        // respected (typically 0 → single space).
                        : b at_top_boundary & == bd 0
                        & == pd 0
                        & ( __pp_starts_top_decl text )
                        & ! prev_was_pub
                        ! == prev_kind TT_FMT_COMMENT
                        // A "compact chain" is two consecutive top-
                        // level decls of the same one-byte starter
                        // (`$` imports, `&` ffi decls, repeated `:`
                        // consts/struct/enum decls). Collapse the
                        // mandatory blank line for these — the
                        // resulting block is the dense token-table
                        // style the codebase already uses.
                        : b compact_chain
                        & ( __pp_text_eq text prev_top_starter )
                        | ( __pp_text_eq text `$` )
                        | ( __pp_text_eq text `&` )
                        ( __pp_text_eq text `:` )
                        ? & at_top_boundary ! compact_chain
                        {
                            = pre_newlines 2
                        } {
                            // Otherwise respect the user's
                            // newline-count, with two specialisations:
                            //   * the empty-pair case keeps both
                            //     tokens on one line with no inner
                            //     space,
                            //   * a comment that follows a same-line
                            //     token gets two leading spaces.
                            ? & == nl 0 ( __pp_is_empty_pair prev_text text ) {
                                = pre_newlines 0
                            } {
                                = pre_newlines nl
                                ? & == nl 0 == kind TT_FMT_COMMENT {
                                    = pre_two_space T
                                } {}
                            }
                        }
                    }

                    // Decide tight-with-previous (no space at all).
                    : ~ b tight_with_prev F
                    // (1) Type-prefix sigil in type position glues to
                    //     the next type token: `*Expr`, `?i`, etc.
                    ? & == pre_newlines 0 prev_is_type_prefix {
                        = tight_with_prev T
                    } {}
                    // (2) Bracket edges — content sits tight against
                    //     the opening `[` and the closing `]`, but
                    //     adjacent tokens INSIDE the brackets stay
                    //     space-separated. This preserves both
                    //     `[ i | 1 2 3 ]` slice literals AND
                    //     `[A B]` / `[T]` type-param lists.
                    ? & == pre_newlines 0 ( __pp_text_eq prev_text `[` ) {
                        = tight_with_prev T
                    } {}
                    ? & == pre_newlines 0 ( __pp_text_eq text `]` ) {
                        = tight_with_prev T
                    } {}
                    // (3) Empty-pair: collapse `( )` / `[ ]` / `{ }`
                    //     to `()` / `[]` / `{}`.
                    ? & == pre_newlines 0 ( __pp_is_empty_pair prev_text text ) {
                        = tight_with_prev T
                    } {}

                    // Emit the inter-token separator.
                    ? > pre_newlines 0 {
                        : ~ i nl_emit pre_newlines
                        ? > nl_emit 2 { = nl_emit 2 } {}
                        : ~ i k 0
                        ~ < k nl_emit {
                            ( string_push_char out 10 )
                            = k + k 1
                        }
                        // Compute indent column. `}` at the start of a
                        // line dedents by one BEFORE printing; the
                        // brace-depth update happens below.
                        : ~ i col_bd bd
                        ? ( __pp_text_eq text `}` ) {
                            ? > col_bd 0 { = col_bd - col_bd 1 } {}
                        } {}
                        ( __pp_indent out * col_bd 4 )
                        = last_line_open F
                    } {
                        ? emitted_any {
                            // Same-line continuation.
                            ? tight_with_prev {
                                // No separator at all.
                            } {
                                ? pre_two_space {
                                    ( string_push_char out 32 )
                                    ( string_push_char out 32 )
                                } {
                                    ( string_push_char out 32 )
                                }
                            }
                        } {}
                    }

                    // Emit the token text verbatim.
                    ( string_push_str out text )
                    = last_line_open F
                    = emitted_any T

                    // Update brace/paren depth AFTER emitting so the
                    // next iteration sees the post-token state.
                    ? ( __pp_text_eq text `{` ) { = bd + bd 1 } {}
                    ? ( __pp_text_eq text `}` ) {
                        ? > bd 0 { = bd - bd 1 } {}
                    } {}
                    ? ( __pp_text_eq text `(` ) { = pd + pd 1 } {}
                    ? ( __pp_text_eq text `[` ) {
                        = pd + pd 1
                        = bk + bk 1
                    } {}
                    ? ( __pp_text_eq text `)` ) {
                        ? > pd 0 { = pd - pd 1 } {}
                    } {}
                    ? ( __pp_text_eq text `]` ) {
                        ? > pd 0 { = pd - pd 1 } {}
                        ? > bk 0 { = bk - bk 1 } {}
                    } {}

                    // Update the type-prefix flag for the NEXT iteration.
                    // The current token is a sigil-in-type-pos when:
                    //   * it is `*`, `?`, `!` AND prev was a type-context
                    //     trigger or itself a sigil-in-type-pos,
                    //   * OR the current token is the type-context trigger
                    //     itself and the NEXT token will be inspected; in
                    //     that case we set the flag for the LAST sigil we
                    //     emit in a sigil chain, not the trigger.
                    // We materialise this as: flag = (curr is *,?,!) AND
                    //   (prev is in trigger set OR prev_is_type_prefix).
                    : b is_sigil
                    | ( __pp_text_eq text `*` )
                    | ( __pp_text_eq text `?` ) ( __pp_text_eq text `!` )
                    : b prev_is_trigger
                    | ( __pp_text_eq prev_text `:` )
                    | ( __pp_text_eq prev_text `→` )
                    | ( __pp_text_eq prev_text `#` )
                    | ( __pp_text_eq prev_text `Z` )
                    | ( __pp_text_eq prev_text `@` )
                    ( __pp_text_eq prev_text `(@` )
                    ? & is_sigil | prev_is_trigger prev_is_type_prefix {
                        = prev_is_type_prefix T
                    } {
                        = prev_is_type_prefix F
                    }

                    // If this token started a top-level decl (it is a
                    // top-decl-starter at bd==0), remember it so the
                    // next boundary can identify `$`-only chains.
                    ? & ( __pp_starts_top_decl text ) == bd 0 {
                        = prev_top_starter text
                    } {}

                    // Track whether the just-emitted token is `pub`
                    // at depth 0 so the following decl-starter knows
                    // to glue. `pub` inside a comment/string never
                    // reaches this path (those are non-IDENT kinds).
                    ? & & == bd 0 == pd 0 ( __pp_text_eq text `pub` ) {
                        = prev_was_pub T
                    } {
                        = prev_was_pub F
                    }

                    = prev_text text
                    = prev_kind kind
                }
            }
            F _ → {}
        }
        = idx + idx 1
    }

    ^ out
}

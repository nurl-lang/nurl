// stdlib/ext/nurldoc.nu — render a NURL module's doc surface to Markdown.
//
// NURL's stdlib follows a consistent discipline — a `//` module-header
// block at the top of each file, top-level declarations, and `//` doc
// comments immediately above them — but that's invisible to anyone not
// reading source. `nurldoc_render` turns one module's text into Markdown:
// the header block as prose, then each top-level declaration's signature
// (the line up to its `{` body) with any preceding doc comment.
//
//   ( nurldoc_render s content s title )  → String   Markdown for one module
//
// What counts as a documentable top-level declaration (brace depth 0,
// so `:` locals inside function bodies are never picked up):
//   @ name … / pub @ name …      functions
//   & `lib` @ name …             FFI externs
//   : Name { … } / : ~ Name …    structs + mutable globals
//   : | Name { … }               enums
//   : TYPE name …                constants
//   % Trait … / % Trait ( T )    trait decls + impls
//
// The renderer is pure (text → text); the `nurldoc` CLI tool walks a
// directory with fs_glob and writes one `.md` per module on top of it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── line helpers ────────────────────────────────────────────────────

// Index of the first non-(space/tab) byte at/after `from` within
// [from,end); returns `end` when the run is all whitespace.
@ __nd_skip_ws s p i from i end → i {
    : ~ i k from
    ~ & < k end | == ( nurl_str_get p k ) 32 == ( nurl_str_get p k ) 9 { = k + k 1 }
    ^ k
}

// True iff p[st..en) begins with the literal `pre`.
@ __nd_starts_with s p i st i en s pre → b {
    : i pn ( nurl_str_len pre )
    ? > + st pn en { ^ F } {}
    : ~ i k 0
    ~ < k pn { ? != ( nurl_str_get p + st k ) ( nurl_str_get pre k ) { ^ F } {} = k + k 1 }
    ^ T
}

// Net brace delta of one line, counting `{`/`}` only in code (outside
// a `//` comment and outside backtick strings). Used to track top-level
// depth across lines.
@ __nd_brace_delta s p i st i en → i {
    : ~ i k st
    : ~ i depth 0
    : ~ i in_str 0
    ~ < k en {
        : i c ( nurl_str_get p k )
        ? != in_str 0 {
            ? == c 96 { = in_str 0 } {}
        } {
            ? == c 96 { = in_str 1 } {
                ? & == c 47 & < + k 1 en == ( nurl_str_get p + k 1 ) 47 { ^ depth } {}  // `//` → rest is comment
                ? == c 123 { = depth + depth 1 } {}
                ? == c 125 { = depth - depth 1 } {}
            }
        }
        = k + k 1
    }
    ^ depth
}

// Append the comment text of a `//` line (with the leading `// ` or `//`
// stripped) to `out`, plus a newline.
@ __nd_push_comment_body String out s p i st i en → v {
    : ~ i k + st 2                            // past `//`
    ? & < k en == ( nurl_str_get p k ) 32 { = k + k 1 } {}  // one optional space
    ~ < k en { ( string_push_char out ( nurl_str_get p k ) ) = k + k 1 }
    ( string_push_char out 10 )
}

// Append the declaration signature in p[st..en) to `out`, trailing
// whitespace trimmed. Functions (`cut_brace` true) stop at the `{` body
// open; types/enums/consts/impls keep the whole line so their `{ … }`
// definition shows.
@ __nd_push_signature String out s p i st i en b cut_brace → v {
    : ~ i brace en
    ? cut_brace {
        : ~ i k st
        : ~ i in_str 0
        : ~ b found F
        ~ & < k en ! found {
            : i c ( nurl_str_get p k )
            ? != in_str 0 { ? == c 96 { = in_str 0 } {} } {
                ? == c 96 { = in_str 1 } {
                    ? == c 123 { = brace k = found T } {}
                }
            }
            = k + k 1
        }
    } {}
    // trim trailing whitespace before the cut point
    : ~ i e brace
    ~ & > e st | | == ( nurl_str_get p - e 1 ) 32 == ( nurl_str_get p - e 1 ) 9 == ( nurl_str_get p - e 1 ) 10 { = e - e 1 }
    : ~ i j st
    ~ < j e { ( string_push_char out ( nurl_str_get p j ) ) = j + j 1 }
}

// First declaration byte at/after `sp`, skipping a leading `pub `, or 0
// when there is none. Shared by __nd_is_decl / __nd_is_fn.
@ __nd_decl_char s p i sp i en → i {
    : ~ i k sp
    ? ( __nd_starts_with p k en `pub ` ) { = k ( __nd_skip_ws p + k 4 en ) } {}
    ? >= k en { ^ 0 } {}
    ^ ( nurl_str_get p k )
}

// Does the line starting at `sp` (first non-ws index) begin a top-level
// declaration? Recognises `@`, `& `, `: `, `% `, and a leading `pub `.
@ __nd_is_decl s p i sp i en → b {
    : i c ( __nd_decl_char p sp en )
    ? | | | == c 64 == c 38 == c 37 == c 58 { ^ T } {}  // @ & % :
    ^ F
}

// Is this decl a function (`@` or `& `-FFI)? Functions hide their `{`
// body in the rendered signature; everything else keeps the full line.
@ __nd_is_fn s p i sp i en → b {
    : i c ( __nd_decl_char p sp en )
    ^ | == c 64 == c 38
}

// ── renderer ────────────────────────────────────────────────────────

@ nurldoc_render s content s title → String {
    : i n ( nurl_str_len content )
    : String out ( string_with_cap + n 256 )
    ( string_push_str out `# ` )
    ( string_push_str out title )
    ( string_push_str out `\n\n` )

    : String header ( string_with_cap 256 )   // top `//` block (module prose)
    : ~ String pending ( string_with_cap 256 )   // doc comment(s) above next decl
    : String body ( string_with_cap + n 256 )  // accumulated "## API" entries

    : ~ i pos 0
    : ~ i depth 0
    : ~ b header_done F   // true once we leave the leading comment block
    : ~ b any_decl F
    : ~ i pending_n 0

    ~ < pos n {
        // line bounds [ls, le); advance pos past the newline
        : i ls pos
        : ~ i le pos
        ~ & < le n != ( nurl_str_get content le ) 10 { = le + le 1 }
        : i sp ( __nd_skip_ws content ls le )
        : b blank == sp le
        : b is_comment & ! blank ( __nd_starts_with content sp le `//` )

        ? == depth 0 {
            ? is_comment {
                ? header_done {
                    ( __nd_push_comment_body pending content sp le )
                    = pending_n + pending_n 1
                } {
                    ( __nd_push_comment_body header content sp le )
                }
            } {
                ? blank {
                    // blank line ends a pending doc block (and the header)
                    = header_done T
                    ( string_free pending )
                    = pending ( string_with_cap 256 )
                    = pending_n 0
                } {
                    = header_done T
                    ? ( __nd_is_decl content sp le ) {
                        = any_decl T
                        ( string_push_str body `### ` )
                        ( string_push_char body 96 )           // markdown `
                        ( __nd_push_signature body content sp le ( __nd_is_fn content sp le ) )
                        ( string_push_char body 96 )
                        ( string_push_str body `\n\n` )
                        ? > pending_n 0 {
                            ( string_push_str body ( string_data pending ) )
                            ( string_push_char body 10 )
                        } {}
                    } {}
                    // any non-decl code line clears the pending doc
                    ( string_free pending )
                    = pending ( string_with_cap 256 )
                    = pending_n 0
                }
            }
        } {}

        = depth + depth ( __nd_brace_delta content ls le )
        ? < depth 0 { = depth 0 } {}
        = pos ? < le n + le 1 le
    }

    ? > ( string_len header ) 0 {
        ( string_push_str out ( string_data header ) )
        ( string_push_char out 10 )
    } {}
    ? any_decl {
        ( string_push_str out `## API\n\n` )
        ( string_push_str out ( string_data body ) )
    } {}

    ( string_free header )
    ( string_free pending )
    ( string_free body )
    ^ out
}

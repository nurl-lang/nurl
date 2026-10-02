// stdlib/std/fmt.nu — `{}` placeholder substitution
//
// `fmt`-family functions take a template string and substitute the
// next raw `s` argument for every `{}` they meet, left-to-right.
// They build an owned `String` you can print, push, return, …
//
// Args are raw `s` (i8*) — string literals work directly; for an
// owned `String` pass `( string_data str )`; for an integer pass
// `( nurl_str_int n )`; for a float `( nurl_str_float x )`.
//
//   ( fmt  tmpl args )       → String   args is `( Vec s )`, dynamic arity
//   ( fmt1 tmpl a )          → String
//   ( fmt2 tmpl a b )        → String
//   ( fmt3 tmpl a b c )      → String
//   ( fmt4 tmpl a b c d )    → String
//
//   ( println_fmt1 tmpl a )           → v   stdout + '\n'
//   ( println_fmt2 tmpl a b )         → v
//   ( println_fmt3 tmpl a b c )       → v
//   ( println_fmt4 tmpl a b c d )     → v
//   ( eprintln_fmt1..4 ... )          → v   same, on stderr
//
// Placeholder rules:
//   `{}`   substitute next argument
//   `{{`   literal `{`
//   `}}`   literal `}`
//
//   - Surplus arguments (more args than `{}` slots) are silently dropped.
//   - Missing arguments emit literal `{}` so the bug is visible.
//   - Stray `{` / `}` (not part of an above sequence) are emitted verbatim.
//
// The String a `fmt*` call builds is the caller's: it is dropped with its
// owner (docs/MEMORY.md §7.6), like any other String. The print helpers
// build, print and drop it in one go.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── Core engine ────────────────────────────────────────────────────

// The template is walked through a raw pointer with its length hoisted
// once. `nurl_str_get` re-runs strlen on every call, and the pushes
// into `out` keep LLVM from hoisting it, so the scan used to be
// quadratic in template length — 9.4 ns per byte on a 512-byte
// template. Short templates hid the cost; HTML-sized ones do not.
//
// The arguments are read where they are: the caller's `( Vec s )` (fmt),
// or — `nfixed` >= 0 — the fixed arguments a0..a3 of fmt1..fmt4, so a
// fixed-arity call copies nothing and a caller's temporary is only read.
@ __fmt_emit String out s tmpl ( Vec s ) args i nfixed s a0 s a1 s a2 s a3 → v {
    : i tlen ( nurl_str_len tmpl )
    : *u tp # *u tmpl
    : i nargs ? < nfixed 0 ( vec_len [s] args ) nfixed
    : ~ i i 0
    : ~ i ai 0
    ~ < i tlen {
        : i c & # i . tp i 255
        // '{' = 123, '}' = 125
        ? == c 123 {
            : i nxt + i 1
            ? < nxt tlen {
                : i c2 & # i . tp nxt 255
                ? == c2 123 {
                    ( string_push_char out 123 )
                    = i + i 2
                } {
                    ? == c2 125 {
                        ? < ai nargs {
                            ( string_push_str out ( __fmt_arg args nfixed a0 a1 a2 a3 ai ) )
                            = ai + ai 1
                        } {
                            ( string_push_char out 123 )
                            ( string_push_char out 125 )
                        }
                        = i + i 2
                    } {
                        ( string_push_char out 123 )
                        = i + i 1
                    }
                }
            } {
                ( string_push_char out 123 )
                = i + i 1
            }
        } {
            ? == c 125 {
                : i nxt + i 1
                ? < nxt tlen {
                    : i c2 & # i . tp nxt 255
                    ? == c2 125 {
                        ( string_push_char out 125 )
                        = i + i 2
                    } {
                        ( string_push_char out 125 )
                        = i + i 1
                    }
                } {
                    ( string_push_char out 125 )
                    = i + i 1
                }
            } {
                // Literal run: copy everything up to the next brace in
                // one memcpy instead of a string_push_char per byte.
                : ~ i run + i 1
                ~ & < run tlen & != & # i . tp run 255 123 != & # i . tp run 255 125 {
                    = run + run 1
                }
                : *u at # *u + # i tp i
                ( string_push_bytes out at - run i )
                = i run
            }
        }
    }
}

// Argument `k` of a __fmt_emit call — lent: the caller's, never a copy.
@ __fmt_arg ( Vec s ) args i nfixed s a0 s a1 s a2 s a3 i k → s {
    ? < nfixed 0 { ^ ?? ( vec_get [s] args k ) { T x → x F → `` } } {}
    ? == k 0 { ^ a0 } {}
    ? == k 1 { ^ a1 } {}
    ? == k 2 { ^ a2 } {}
    ^ a3
}

// ── Public API ─────────────────────────────────────────────────────

@ fmt s tmpl ( Vec s ) args → String {
    : String out ( string_new )
    ( __fmt_emit out tmpl args -1 `` `` `` `` )
    ^ out
}

@ fmt1 s tmpl s a → String {
    : String out ( string_new )
    ( __fmt_emit out tmpl # ( Vec s ) 0 1 a `` `` `` )
    ^ out
}

@ fmt2 s tmpl s a s b → String {
    : String out ( string_new )
    ( __fmt_emit out tmpl # ( Vec s ) 0 2 a b `` `` )
    ^ out
}

@ fmt3 s tmpl s a s b s c → String {
    : String out ( string_new )
    ( __fmt_emit out tmpl # ( Vec s ) 0 3 a b c `` )
    ^ out
}

@ fmt4 s tmpl s a s b s c s d → String {
    : String out ( string_new )
    ( __fmt_emit out tmpl # ( Vec s ) 0 4 a b c d )
    ^ out
}

// ── Print helpers (build, print + '\n') ────────────────────────────

@ println_fmt1 s tmpl s a → v {
    : String r ( fmt1 tmpl a )
    ( nurl_print ( string_data r ) )
    ( nurl_print `\n` )
}

@ println_fmt2 s tmpl s a s b → v {
    : String r ( fmt2 tmpl a b )
    ( nurl_print ( string_data r ) )
    ( nurl_print `\n` )
}

@ println_fmt3 s tmpl s a s b s c → v {
    : String r ( fmt3 tmpl a b c )
    ( nurl_print ( string_data r ) )
    ( nurl_print `\n` )
}

@ println_fmt4 s tmpl s a s b s c s d → v {
    : String r ( fmt4 tmpl a b c d )
    ( nurl_print ( string_data r ) )
    ( nurl_print `\n` )
}

@ eprintln_fmt1 s tmpl s a → v {
    : String r ( fmt1 tmpl a )
    ( nurl_eprint ( string_data r ) )
    ( nurl_eprint `\n` )
}

@ eprintln_fmt2 s tmpl s a s b → v {
    : String r ( fmt2 tmpl a b )
    ( nurl_eprint ( string_data r ) )
    ( nurl_eprint `\n` )
}

@ eprintln_fmt3 s tmpl s a s b s c → v {
    : String r ( fmt3 tmpl a b c )
    ( nurl_eprint ( string_data r ) )
    ( nurl_eprint `\n` )
}

@ eprintln_fmt4 s tmpl s a s b s c s d → v {
    : String r ( fmt4 tmpl a b c d )
    ( nurl_eprint ( string_data r ) )
    ( nurl_eprint `\n` )
}

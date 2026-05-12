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
//   ( println_fmt1 tmpl a )           → v   stdout + '\n', frees String
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
// `fmt`-family allocate; the print helpers free for you. When you build
// with `fmt*` directly, the caller is responsible for `string_free`.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

// ── Core engine ────────────────────────────────────────────────────

@ __fmt_emit String out s tmpl ( Vec s ) args → v {
  : i tlen ( nurl_str_len tmpl )
  : i nargs ( vec_len [s] args )
  : ~ i i 0
  : ~ i ai 0
  ~ < i tlen {
    : i c ( nurl_str_get tmpl i )
    // '{' = 123, '}' = 125
    ? == c 123 {
      : i nxt + i 1
      ? < nxt tlen {
        : i c2 ( nurl_str_get tmpl nxt )
        ? == c2 123 {
          ( string_push_char out 123 )
          = i + i 2
        } {
          ? == c2 125 {
            ? < ai nargs {
              : ? s got ( vec_get [s] args ai )
              ?? got {
                T sa → ( string_push_str out sa )
                F → {}
              }
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
          : i c2 ( nurl_str_get tmpl nxt )
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
        ( string_push_char out c )
        = i + i 1
      }
    }
  }
}

// ── Public API ─────────────────────────────────────────────────────

@ fmt s tmpl ( Vec s ) args → String {
  : String out ( string_new )
  ( __fmt_emit out tmpl args )
  ^ out
}

@ fmt1 s tmpl s a → String {
  : ( Vec s ) v ( vec_with_cap [s] 1 )
  ( vec_push [s] v a )
  : String r ( fmt tmpl v )
  ( vec_free [s] v )
  ^ r
}

@ fmt2 s tmpl s a s b → String {
  : ( Vec s ) v ( vec_with_cap [s] 2 )
  ( vec_push [s] v a )
  ( vec_push [s] v b )
  : String r ( fmt tmpl v )
  ( vec_free [s] v )
  ^ r
}

@ fmt3 s tmpl s a s b s c → String {
  : ( Vec s ) v ( vec_with_cap [s] 3 )
  ( vec_push [s] v a )
  ( vec_push [s] v b )
  ( vec_push [s] v c )
  : String r ( fmt tmpl v )
  ( vec_free [s] v )
  ^ r
}

@ fmt4 s tmpl s a s b s c s d → String {
  : ( Vec s ) v ( vec_with_cap [s] 4 )
  ( vec_push [s] v a )
  ( vec_push [s] v b )
  ( vec_push [s] v c )
  ( vec_push [s] v d )
  : String r ( fmt tmpl v )
  ( vec_free [s] v )
  ^ r
}

// ── Print helpers (build, print + '\n', free) ──────────────────────

@ println_fmt1 s tmpl s a → v {
  : String r ( fmt1 tmpl a )
  ( nurl_print ( string_data r ) )
  ( nurl_print `\n` )
  ( string_free r )
}

@ println_fmt2 s tmpl s a s b → v {
  : String r ( fmt2 tmpl a b )
  ( nurl_print ( string_data r ) )
  ( nurl_print `\n` )
  ( string_free r )
}

@ println_fmt3 s tmpl s a s b s c → v {
  : String r ( fmt3 tmpl a b c )
  ( nurl_print ( string_data r ) )
  ( nurl_print `\n` )
  ( string_free r )
}

@ println_fmt4 s tmpl s a s b s c s d → v {
  : String r ( fmt4 tmpl a b c d )
  ( nurl_print ( string_data r ) )
  ( nurl_print `\n` )
  ( string_free r )
}

@ eprintln_fmt1 s tmpl s a → v {
  : String r ( fmt1 tmpl a )
  ( nurl_eprint ( string_data r ) )
  ( nurl_eprint `\n` )
  ( string_free r )
}

@ eprintln_fmt2 s tmpl s a s b → v {
  : String r ( fmt2 tmpl a b )
  ( nurl_eprint ( string_data r ) )
  ( nurl_eprint `\n` )
  ( string_free r )
}

@ eprintln_fmt3 s tmpl s a s b s c → v {
  : String r ( fmt3 tmpl a b c )
  ( nurl_eprint ( string_data r ) )
  ( nurl_eprint `\n` )
  ( string_free r )
}

@ eprintln_fmt4 s tmpl s a s b s c s d → v {
  : String r ( fmt4 tmpl a b c d )
  ( nurl_eprint ( string_data r ) )
  ( nurl_eprint `\n` )
  ( string_free r )
}

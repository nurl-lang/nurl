# `argz` — a tiny command-line argument parser

`argz` is a small, **dependency-free** argument parser for NURL CLIs.
Clap-shaped but deliberately tiny: boolean flags, value options
(`--name X` and `--name=X`), short aliases (`-n`), a `--` end-of-options
separator, positional arguments, and an auto-generated `--help` body.

It lives in the NURL registry (it is *not* part of the core stdlib): every
CLI wants argument parsing, but the shape of a parser is opinionated enough
that it belongs to the ecosystem, not the language. It is leak-clean under
AddressSanitizer/LeakSanitizer.

```toml
[dependencies]
argz = "^0.1"
```

```
$ `deps/argz/src/argz.nu`
```

## API

```
( argz_new prog about )                  → Argz
( argz_flag p long short help )          → v        boolean flag  (--long / -short)
( argz_opt  p long short help )          → v        value option  (--long V / --long=V)
( argz_parse p argv )                    → ! ArgzMatch ArgzErr
( argz_has   m long )                    → b        flag/option present?
( argz_value m long )                    → ?String  value of an option (borrows)
( argz_positionals m )                   → ( Vec String )  positionals, in order (borrows)
( argz_help  p )                         → String   rendered usage text
( argz_err_name e )                      → s        name of an ArgzErr
( argz_free p ) / ( argz_match_free m )  → v        free the parser / the match
```

`short` may be empty (`""`), meaning the spec has no short alias. Option
values and positionals returned by the accessors **borrow** the match's
storage — do not free them; `argz_match_free` owns the whole match.

`argz_parse` fails with an `ArgzErr` of either `ArgzUnknownFlag` (a
`--flag` / `-f` not registered) or `ArgzMissingValue` (a value option with
no value after it).

## Example

```
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `deps/argz/src/argz.nu`

@ main → i {
    : Argz p ( argz_new `greet` `a friendly greeter` )
    ( argz_flag p `shout` `s` `upper-case the greeting` )
    ( argz_opt  p `name`  `n` `who to greet` )

    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i i 1
    ~ < i ac { ( vec_push [String] argv ( env_arg i ) ) = i + i 1 }

    : ~ i rc 0
    ?? ( argz_parse p argv ) {
        F e → { ( nurl_eprintln ( argz_err_name e ) ) = rc 2 }
        T m → {
            ?? ( argz_value m `name` ) {
                T nv → { ( nurl_print `Hello, ` ) ( nurl_print ( string_data nv ) ) ( nurl_print `!\n` ) }
                F _ → { ( nurl_print `Hello, World!\n` ) }
            }
            ( argz_match_free m )
        }
    }
    ( argz_free p )
    ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
    ^ rc
}
```

See [`argz-demo`](../argz-demo) for a complete installable program built on
`argz`.

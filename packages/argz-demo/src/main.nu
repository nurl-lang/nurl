// argz-demo — a tiny installable CLI built on the `argz` registry package.
//
// Demonstrates the full ecosystem loop: this program declares `argz` as a
// registry dependency (see nurl.toml), and `nurlpkg install argz-demo`
// fetches it, resolves `argz` into ./deps/, compiles this entry point
// against the installed stdlib, and drops a `greet` binary on $PATH.
//
//   greet --name World           → Hello, World!
//   greet --name World --shout    → HELLO, WORLD!
//   greet alice bob               → Hello, alice! / Hello, bob!

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `deps/argz/src/argz.nu`

@ __greet s who b shout → v {
    : String line ( string_with_cap 32 )
    ( string_push_str line `Hello, ` )
    ( string_push_str line who )
    ( string_push_char line 33 )
    ? shout {
        : String up ( string_to_upper line )
        ( nurl_print ( string_data up ) ) ( nurl_print `\n` )
        ( string_free up )
    } {
        ( nurl_print ( string_data line ) ) ( nurl_print `\n` )
    }
    ( string_free line )
}

@ main → i {
    : Argz p ( argz_new `argz-demo` `friendly greeter (argz demo)` )
    ( argz_flag p `shout` `s` `upper-case the greeting` )
    ( argz_flag p `help` `h` `show this help` )
    ( argz_opt  p `name` `n` `a single name to greet` )

    // Real process argv, minus argv[0].
    : ( Vec String ) argv ( vec_new [String] )
    : i ac ( env_args_count )
    : ~ i i 1
    ~ < i ac {
        ( vec_push [String] argv ( env_arg i ) )
        = i + i 1
    }

    : ~ i rc 0
    : !ArgzMatch ArgzErr r ( argz_parse p argv )
    ?? r {
        F e → {
            ( nurl_eprint `greet: ` ) ( nurl_eprintln ( argz_err_name e ) )
            = rc 2
        }
        T m → {
            ? ( argz_has m `help` ) {
                : String h ( argz_help p )
                ( nurl_print ( string_data h ) )
                ( string_free h )
            } {
                : b shout ( argz_has m `shout` )
                : ~ b greeted F
                ?? ( argz_value m `name` ) {
                    T nv → { ( __greet ( string_data nv ) shout ) = greeted T }
                    F _ → {}
                }
                : ( Vec String ) ps ( argz_positionals m )
                : i np ( vec_len [String] ps )
                : ~ i k 0
                ~ < k np {
                    ?? ( vec_get [String] ps k ) {
                        T pv → { ( __greet ( string_data pv ) shout ) = greeted T }
                        F _ → {}
                    }
                    = k + k 1
                }
                ? ! greeted { ( __greet `World` shout ) } {}
            }
            ( argz_match_free m )
        }
    }
    ( argz_free p )
    ( vec_free_with [String] argv \ String x → v { ( string_free x ) } )
    ^ rc
}

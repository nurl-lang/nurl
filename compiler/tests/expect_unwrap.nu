// expect_unwrap.nu — the leaf-site error-handling combinators (critic M13):
// res_expect / res_unwrap / res_unwrap_or_else / res_ok / res_err and
// opt_expect / opt_unwrap / opt_unwrap_or_else / opt_ok_or. Happy paths
// return the payload; the panicking paths are caught with recover and the
// message round-trips. A struct payload checks the `. r 1` extraction on
// aggregates, not just scalars.

$ `stdlib/core/option.nu`
$ `stdlib/core/result.nu`
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Point { i x i y }

@ ok_i → !i s {
    ^ @ !i s { T 42 }
}

@ err_i → !i s {
    ^ @ !i s { F `boom` }
}

@ some_p → ?Point {
    ^ @ ?Point { T @ Point { 3 4 } }
}

@ none_i → ?i {
    ^ @ ?i { F }
}

@ main → i {
    // ── happy paths ──────────────────────────────────────────────
    ( nurl_print `expect ok: ` )
    ( nurl_println_int ( res_expect [i s] ( ok_i ) `should not fire` ) )
    ( nurl_print `unwrap ok: ` )
    ( nurl_println_int ( res_unwrap [i s] ( ok_i ) ) )
    : Point p ( opt_expect [Point] ( some_p ) `should not fire` )
    ( nurl_print `opt expect struct: ` )
    ( nurl_println_int + . p x . p y )

    // ── or_else fallbacks ────────────────────────────────────────
    ( nurl_print `res or_else: ` )
    ( nurl_println_int ( res_unwrap_or_else [i s] ( err_i ) \ s _e → i { ^ -1 } ) )
    ( nurl_print `opt or_else: ` )
    ( nurl_println_int ( opt_unwrap_or_else [i] ( none_i ) \ → i { ^ -2 } ) )

    // ── bridges ──────────────────────────────────────────────────
    ( nurl_print `res_ok some: ` )
    ( nurl_println_int ( opt_unwrap_or [i] ( res_ok [i s] ( ok_i ) ) 0 ) )
    ( nurl_print `res_err some: ` )
    ( nurl_print ( opt_unwrap_or [s] ( res_err [i s] ( err_i ) ) `none` ) )
    ( nurl_print `\n` )
    ( nurl_print `ok_or err: ` )
    : !i s bridged ( opt_ok_or [i s] ( none_i ) `was-none` )
    ?? bridged {
        T v → ( nurl_println_int v )
        F e → ( nurl_print e )
    }
    ( nurl_print `\n` )

    // ── panic paths, caught ──────────────────────────────────────
    : !v PanicInfo r1 ( recover \ → v { : i _x ( res_expect [i s] ( err_i ) `parse the config` ) } )
    ?? r1 {
        T _ → ( nurl_print `expect: no panic (bug)\n` )
        F pi → {
            ( nurl_print `expect panicked: ` )
            ( nurl_print ( string_data . pi msg ) )
            ( nurl_print `\n` )
            ( panic_info_free pi )
        }
    }
    : !v PanicInfo r2 ( recover \ → v { : i _y ( opt_unwrap [i] ( none_i ) ) } )
    ?? r2 {
        T _ → ( nurl_print `unwrap: no panic (bug)\n` )
        F pi → {
            ( nurl_print `unwrap panicked: ` )
            ( nurl_print ( string_data . pi msg ) )
            ( nurl_print `\n` )
            ( panic_info_free pi )
        }
    }
    ( nurl_print `alive\n` )
    ^ 0
}

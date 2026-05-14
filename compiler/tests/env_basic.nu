// env_basic.nu — exercises stdlib/ext/env.nu
//
// Expected output:
//   args_count >= 1: T
//   missing var: not set
//   set/get: hello world
//   var_or default: fallback
//   var_or set: hello world
//   unset/get: not set
//   chdir bad: not found

$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/errors.nu`

@ show_opt s label ? String got → v {
    ( nurl_print label )
    ( nurl_print `: ` )
    ?? got {
        T s → {
            ( nurl_print ( string_data s ) )
            ( string_free s )
        }
        F → ( nurl_print `not set` )
    }
    ( nurl_print `\n` )
}

@ main → i {
    : i ac ( env_args_count )
    ( nurl_print `args_count >= 1: ` )
    ? >= ac 1 { ( nurl_print `T` ) } { ( nurl_print `F` ) }
    ( nurl_print `\n` )

    // Use a name unlikely to exist in the host environment.
    : s key `NURL_TEST_VAR_42`

    : ?String empty1 ( env_get key )
    ( show_opt `missing var` empty1 )

    : !v IoErr setres ( env_set key `hello world` )
    ?? setres {
        T → {}
        F e → {
            ( nurl_print `set failed: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    : ?String got1 ( env_get key )
    ( show_opt `set/get` got1 )

    : String fb1 ( env_var_or `NURL_TEST_NOPE_99` `fallback` )
    ( nurl_print `var_or default: ` )
    ( nurl_print ( string_data fb1 ) )
    ( nurl_print `\n` )
    ( string_free fb1 )

    : String fb2 ( env_var_or key `default` )
    ( nurl_print `var_or set: ` )
    ( nurl_print ( string_data fb2 ) )
    ( nurl_print `\n` )
    ( string_free fb2 )

    : !v IoErr unsetres ( env_unset key )
    ?? unsetres {
        T → {}
        F e → {
            ( nurl_print `unset failed: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    : ?String empty2 ( env_get key )
    ( show_opt `unset/get` empty2 )

    : !v IoErr cd ( env_chdir `nurl_does_not_exist_xyz_42` )
    ?? cd {
        T → ( nurl_print `chdir bad: unexpected ok\n` )
        F e → {
            ( nurl_print `chdir bad: ` )
            ( nurl_print ( io_err_msg # IoErr e ) )
            ( nurl_print `\n` )
        }
    }

    ^ 0
}

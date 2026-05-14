// process_basic.nu — exercises stdlib/std/process.nu.
//
// Designed to be deterministic on any POSIX host: relies on bare
// `echo`, `sh`, `cat`, `true`, `false`, plus a known-missing command
// name. The test runner cwd is build/tests, but execvp searches PATH
// so these resolve regardless of layout.

$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`

@ print_int_line s label i n → v {
    ( nurl_print label )
    ( nurl_print `=` )
    : s txt ( nurl_str_int n )
    ( nurl_print txt )
    ( nurl_print `\n` )
}

@ print_bool_line s label b v → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ? v `T` `F` )
    ( nurl_print `\n` )
}

@ print_capture_line s label s buf i n → v {
    ( nurl_print label )
    ( nurl_print `=<` )
    ? > n 0 { ( nurl_print buf ) } {}
    ( nurl_print `>\n` )
}

@ show_output s tag Output o → v {
    ( print_int_line tag ( output_exit_code o ) )
    ( print_bool_line tag ( output_success o ) )
    ( print_capture_line tag ( output_stdout o ) ( output_stdout_len o ) )
    ( print_capture_line tag ( output_stderr o ) ( output_stderr_len o ) )
}

@ show_err s tag ProcessErr e → v {
    ( nurl_print tag )
    ( nurl_print `=err:` )
    ( nurl_print ( process_err_name e ) )
    ( nurl_print `\n` )
}

@ main → i {
    // 1. echo with one literal arg.
    : !Output ProcessErr r1 ( process_run1 `echo` `hello world` )
    ?? r1 {
        T o → { ( show_output `1` o ) ( output_free o ) }
        F e → ( show_err `1` # ProcessErr e )
    }

    // 2. process_run0 → no args, exit 0.
    : !Output ProcessErr r2 ( process_run0 `true` )
    ?? r2 {
        T o → { ( show_output `2` o ) ( output_free o ) }
        F e → ( show_err `2` # ProcessErr e )
    }

    // 3. process_run0 → no args, non-zero exit.
    : !Output ProcessErr r3 ( process_run0 `false` )
    ?? r3 {
        T o → { ( show_output `3` o ) ( output_free o ) }
        F e → ( show_err `3` # ProcessErr e )
    }

    // 4. shell pipeline: write to stderr, non-zero exit.
    //    `printf` is mandated by POSIX shells.
    : !Output ProcessErr r4 ( process_run_shell `printf oops 1>&2; exit 7` )
    ?? r4 {
        T o → { ( show_output `4` o ) ( output_free o ) }
        F e → ( show_err `4` # ProcessErr e )
    }

    // 5. stdin → cat → stdout.
    : ( Vec s ) cat_args ( vec_new [s] )
    : !Output ProcessErr r5 ( process_run `cat` cat_args `from stdin\n` )
    ( vec_free [s] cat_args )
    ?? r5 {
        T o → { ( show_output `5` o ) ( output_free o ) }
        F e → ( show_err `5` # ProcessErr e )
    }

    // 6. multi-arg run: sh -c with a tiny script.
    : !Output ProcessErr r6 ( process_run2 `sh` `-c` `echo a; echo b` )
    ?? r6 {
        T o → { ( show_output `6` o ) ( output_free o ) }
        F e → ( show_err `6` # ProcessErr e )
    }

    // 7. missing command → ProcessNotFound.
    : !Output ProcessErr r7 ( process_run0 `nurl_does_not_exist_xyz_42` )
    ?? r7 {
        T o → { ( show_output `7-unexpected` o ) ( output_free o ) }
        F e → ( show_err `7` # ProcessErr e )
    }

    // 8. empty cmd → ProcessNotFound (handled in runtime).
    : !Output ProcessErr r8 ( process_run0 `` )
    ?? r8 {
        T o → { ( show_output `8-unexpected` o ) ( output_free o ) }
        F e → ( show_err `8` # ProcessErr e )
    }

    ^ 0
}

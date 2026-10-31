// fixture: module; The client side of the loopback server tests (agora #123).
//
// Those tests used to write POSIX shell into process_run_shell: a
// background `{ python3 -c … > /tmp/x.part; mv …; } &`, then a
// `for … seq … sleep 0.05; cat /tmp/…` loop waiting for it. That shell is
// cmd.exe on Windows, so the HTTP and TLS server suites never ran there.
// None of it needs a shell. The client is a child process started with an
// argument vector (no quoting), it runs beside the server because
// process_spawn does not wait for it, and what it printed comes back over
// its own stdout pipe: no temp files and no polling.
$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// Start `python3 -c <src>`; it runs while the caller accepts and serves.
@ py_client_spawn s src → !ProcChild ProcessErr {
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `-c` )
    ( vec_push [s] args src )
    ^ ( process_spawn `python3` args )
}

// Everything the child printed, once it closes its stdout or
// `timeout_ms` passes with nothing new; then the child is reaped. A child
// still running at the timeout is killed: the test fails on its output, it
// does not hang. `ends` is what follows each line: `\n` gives the output
// as printed (newline-terminated lines), `` joins nothing, and
// client_collect joins lines with '\n' and drops the last one's, so a
// one-line answer reads as that line.
@ __client_read ProcChild p i timeout_ms b terminate → String {
    : String out ( string_new )
    : ~ i lines 0
    : ~ b more T
    ~ more {
        : ?String got ( proc_read_line p timeout_ms )
        ?? got {
            T s → {
                ? & ! terminate > lines 0 { ( string_push_str out `\n` ) } {}
                ( string_push_str out ( string_data s ) )
                ? terminate { ( string_push_str out `\n` ) } {}
                ( string_free s )
                = lines + lines 1
            }
            F _ → {
                ? ! ( proc_eof p ) { ( proc_kill p 9 ) } {}
                = more F
            }
        }
    }
    ( proc_wait p )
    ^ out
}

// The child's lines joined by '\n', no trailing newline.
@ client_collect ProcChild p i timeout_ms → String { ^ ( __client_read p timeout_ms F ) }

// The child's output as printed: every line ends with '\n'.
@ client_collect_text ProcChild p i timeout_ms → String { ^ ( __client_read p timeout_ms T ) }

// `openssl req -nodes -x509 -days 1 -newkey <newkey> [-pkeyopt <opt>]
// -keyout <key> -out <crt> -subj /CN=<cn>`, run without a shell. `newkey`
// is `rsa:2048` or `ec`, `opt` an EC curve (`ec_paramgen_curve:prime256v1`)
// or ``. T when openssl made both files.
@ openssl_selfsigned s newkey s opt s key s crt s cn → b {
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `req` ) ( vec_push [s] args `-nodes` ) ( vec_push [s] args `-x509` )
    ( vec_push [s] args `-days` ) ( vec_push [s] args `1` )
    ( vec_push [s] args `-newkey` ) ( vec_push [s] args newkey )
    ? > ( nurl_str_len opt ) 0 { ( vec_push [s] args `-pkeyopt` ) ( vec_push [s] args opt ) } {}
    ( vec_push [s] args `-keyout` ) ( vec_push [s] args key )
    ( vec_push [s] args `-out` ) ( vec_push [s] args crt )
    : String subj ( string_from `/CN=` )
    ( string_push_str subj cn )
    : s subj_v ( string_data subj )
    ( vec_push [s] args `-subj` ) ( vec_push [s] args subj_v )
    : !Output ProcessErr r ( process_run `openssl` args `` )
    ?? r {
        T o → { : i ec ( output_exit_code o ) ( output_free o ) ^ == ec 0 }
        F _ → { ^ F }
    }
}

// What a program printed, with the CRLF line ends of a text-mode stdout
// on Windows (python3, openssl) read as the '\n' the golden compares.
@ client_text s raw → String {
    : String t ( string_from raw )
    ^ ( string_replace t `\r\n` `\n` )
}

// Run `python3 -c <src>` to completion (the server runs on other threads
// meanwhile); what it printed, as client_text reads it. A failed start
// is printed as `<label>=<error>` and reads as nothing.
@ py_run s src s label → String {
    : ( Vec s ) args ( vec_new [s] )
    ( vec_push [s] args `-c` )
    ( vec_push [s] args src )
    : !Output ProcessErr r ( process_run `python3` args `` )
    ?? r {
        T o → {
            : String t ( client_text ( output_stdout o ) )
            ( output_free o )
            ^ t
        }
        F e → {
            ( nurl_print label ) ( nurl_print `=` ) ( nurl_print ( process_err_name e ) ) ( nurl_print `\n` )
            ^ ( string_new )
        }
    }
}

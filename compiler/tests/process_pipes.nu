// process_pipes.nu — critic B11: streaming subprocess pipes.
//
// Exercises incremental stdin-write / stdout-read on a LIVE child via
// proc_write_str / proc_write_bytes / proc_read_chunk / proc_close_stdin
// (stdlib/std/process.nu duplex API).
//
// Deterministic on POSIX hosts:
//   1. `cat` — TWO interactive round-trips: write a line, read the echo,
//      write another, read again. cat only echoes after each write, so a
//      batch-capture implementation would block forever on the first
//      read — this locks true streaming.
//   2. `sort` — write "b\na\n", close stdin, then read everything. sort
//      cannot emit anything before seeing EOF, locking that
//      proc_close_stdin really delivers EOF to the child.
// Both exit statuses are printed. All Vecs/handles are freed (suite
// runs under ASan/LSan).

$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`

@ str_to_vec s in → ( Vec u ) {
    : i n ( nurl_str_len in )
    : ( Vec u ) out ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i k 0
    ~ < k n { ( vec_push [u] out # u ( nurl_str_get in k ) ) = k + k 1 }
    ^ out
}

@ println s line → v {
    ( nurl_print line )
    ( nurl_print `\n` )
}

@ print_int_line s label i n → v {
    ( nurl_print label )
    ( nurl_print `=` )
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )
}

// Read one chunk from the live child and print it bracketed (the
// trailing newline from the child stays inside the brackets). Returns
// bytes read: 0 ⇒ EOF, -1 ⇒ error.
@ read_chunk ProcChild p s tag → i {
    : ~ i got -1
    : !( Vec u ) ProcessErr r ( proc_read_chunk p 4096 )
    ?? r {
        T buf → {
            = got ( vec_len [u] buf )
            ( nurl_print tag )
            ? > got 0 {
                : String txt ( string_from_bytes ( vec_data [u] buf ) got )
                ( nurl_print `=<` )
                ( nurl_print ( string_data txt ) )
                ( nurl_print `>\n` )
                ( string_free txt )
            } {
                ( nurl_print `=eof\n` )
            }
            ( vec_free [u] buf )
        }
        F e → {
            ( nurl_print tag )
            ( nurl_print `=err:` )
            ( nurl_print ( process_err_name e ) )
            ( nurl_print `\n` )
        }
    }
    ^ got
}

// Windows always exports OS=Windows_NT; nothing else does.
@ is_windows → b {
    : ~ b w F
    ?? ( env_get `OS` ) {
        T e → { = w ( nurl_str_eq ( string_data e ) `Windows_NT` ) ( string_free e ) }
        F → {}
    }
    ^ w
}

@ main → i {
    // proc_read_chunk is the POSIX-only half of the duplex API (Win32
    // returns ProcessOther), and both children here are POSIX tools.
    ? ( is_windows ) { ( println `skip=posix-only-read-chunk` ) ^ 0 } {}

    // ── 1. cat: two round-trips on a LIVE child (proves streaming). ──
    : !ProcChild ProcessErr r1 ( process_spawn0 `cat` )
    ?? r1 {
        T child → {
            ( println `=== cat round-trips ===` )
            ( print_int_line `w1` ( proc_write_str child `hello\n` ) )
            ( read_chunk child `r1` )
            ( print_int_line `w2` ( proc_write_str child `world\n` ) )
            ( read_chunk child `r2` )
            ( proc_close_stdin child )
            ( read_chunk child `r3` )
            : i ec ( proc_wait child )
            ( print_int_line `cat_exit` ec )
            ( proc_free child )
        }
        F e → {
            ( nurl_print `cat-spawn-failed=` )
            ( nurl_print ( process_err_name e ) )
            ( nurl_print `\n` )
        }
    }

    // ── 2. sort: no output until stdin EOF, then everything at once. ──
    : !ProcChild ProcessErr r2 ( process_spawn0 `sort` )
    ?? r2 {
        T child → {
            ( println `=== sort after close-stdin ===` )
            : ( Vec u ) lines ( str_to_vec `b\na\n` )
            ( print_int_line `w3` ( proc_write_bytes child lines ) )
            ( vec_free [u] lines )
            ( proc_close_stdin child )
            : ~ i n 1
            ~ > n 0 { = n ( read_chunk child `s` ) }
            : i ec ( proc_wait child )
            ( print_int_line `sort_exit` ec )
            ( proc_free child )
        }
        F e → {
            ( nurl_print `sort-spawn-failed=` )
            ( nurl_print ( process_err_name e ) )
            ( nurl_print `\n` )
        }
    }

    ^ 0
}

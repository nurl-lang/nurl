// process_spawn_self.nu — the duplex-stdio child API (process_spawn /
// proc_write_line / proc_read_line / proc_kill / proc_wait / proc_free)
// driven against a child that is THIS BINARY, re-executed with a marker
// argument.
//
// Why self-spawn rather than `cat`: process_spawn_basic.nu drives POSIX
// tools, so on Windows it could only ever record what the platform did
// NOT do — and for three releases that recording was
// "cat-spawn-failed=ProcessOther", a permanently green golden for a
// backend that was a stub returning ProcessOther before it tried
// anything. `nurl upgrade` on Windows died on that stub. A child that
// ships with the test needs no platform tools, so ONE golden covers
// every host and the Win32 spawn backend is actually exercised.
//
// Every line printed is platform-invariant: no foreign tool's exit
// status, and no signal number — Windows has no signals, so proc_kill
// terminates the child and the test asserts only that the status is
// non-zero.

$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/ext/env.nu`

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

@ print_line s label s text → v {
    ( nurl_print label )
    ( nurl_print `=<` )
    ( nurl_print text )
    ( nurl_print `>\n` )
}

// Child mode: copy stdin to stdout, then exit. `read_all_stdin` returns
// at EOF, so a parent that never closes stdin leaves this child parked
// with nothing to say — which is exactly what the timeout/kill leg
// needs, with no sleep and no race.
@ child_echo → i {
    : String all ( read_all_stdin )
    ( nurl_print ( string_data all ) )
    ( flush )
    ( string_free all )
    ^ 0
}

@ read_one ProcChild p s tag → v {
    : ?String got ( proc_read_line p 5000 )
    ?? got {
        T s → { ( print_line tag ( string_data s ) ) ( string_free s ) }
        F _ → {
            ? ( proc_eof p ) { ( println `eof` ) } { ( println `timeout` ) }
        }
    }
}

@ main → i {
    : String mode ( env_arg 1 )
    : b is_child ( nurl_str_eq ( string_data mode ) `--echo-stdin` )
    ( string_free mode )
    ? is_child { ^ ( child_echo ) } {}

    // argv[0] is how the runner launched us — "./name" on POSIX, a full
    // path on Windows. Both are what the platform's own PATH search
    // resolves, which is the point: the test spawns exactly itself.
    : String self ( env_arg 0 )

    // ── 1. Round-trip 3 lines through the duplex pipes. ───────────────
    : !ProcChild ProcessErr r1 ( process_spawn1 ( string_data self ) `--echo-stdin` )
    ?? r1 {
        T child → {
            ( println `=== self echo ===` )
            ( print_int_line `pid_present` ? > ( proc_pid child ) 0 1 0 )

            ( proc_write_line child `alpha` )
            ( proc_write_line child `beta` )
            ( proc_write_line child `gamma` )
            ( proc_close_stdin child )

            ( read_one child `r1` )
            ( read_one child `r2` )
            ( read_one child `r3` )

            // All three delivered — the next read must see EOF.
            : ?String tail ( proc_read_line child 5000 )
            ?? tail {
                T s → { ( print_line `r4-unexpected` ( string_data s ) ) ( string_free s ) }
                F _ → {
                    ? ( proc_eof child ) { ( println `r4=eof` ) } { ( println `r4=timeout` ) }
                }
            }

            : i ec ( proc_wait child )
            ( print_int_line `child_exit` ec )
            ( proc_free child )
        }
        F e → {
            ( nurl_print `self-spawn-failed=` )
            ( nurl_print ( process_err_name e ) )
            ( nurl_print `\n` )
        }
    }

    // ── 2. Missing command — the error path. ──────────────────────────
    : !ProcChild ProcessErr r2 ( process_spawn0 `nurl_does_not_exist_xyz_42` )
    ?? r2 {
        T child → {
            ( println `unexpected_spawn_ok` )
            ( proc_free child )
        }
        F e → {
            ( nurl_print `missing_err=` )
            ( nurl_print ( process_err_name e ) )
            ( nurl_print `\n` )
        }
    }

    // ── 3. Timeout, then kill: the child waits on a stdin we hold. ────
    : !ProcChild ProcessErr r3 ( process_spawn1 ( string_data self ) `--echo-stdin` )
    ?? r3 {
        T child → {
            : ?String none1 ( proc_read_line child 200 )
            ?? none1 {
                T s → { ( print_line `r3-unexpected` ( string_data s ) ) ( string_free s ) }
                F _ → {
                    ? ( proc_eof child ) { ( println `timeout=eof` ) } { ( println `timeout=ok` ) }
                }
            }
            ( proc_kill child 15 )
            : i ec ( proc_wait child )
            ( print_int_line `kill_nonzero` ? != ec 0 1 0 )
            ( proc_free child )
        }
        F _ → ( println `timeout-spawn-failed` )
    }

    ( string_free self )
    ^ 0
}

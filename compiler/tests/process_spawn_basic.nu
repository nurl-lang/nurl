// process_spawn_basic.nu — exercises the duplex-stdio child API in
// stdlib/std/process.nu (process_spawn / proc_write_line / proc_read_line
// / proc_wait / proc_free).
//
// Deterministic on POSIX hosts: relies on `cat` (echo back stdin) and a
// known-missing command for the error path. Stdin is closed before the
// reader loop so `cat` exits cleanly with status 0.

$ `stdlib/std/process.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

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

@ read_one ProcChild p s tag → v {
  : ? String got ( proc_read_line p 5000 )
  ?? got {
    T s → { ( print_line tag ( string_data s ) ) ( string_free s ) }
    F _ → {
      ? ( proc_eof p ) { ( println `eof` ) } { ( println `timeout` ) }
    }
  }
}

@ main → i {
  // ── 1. Spawn `cat`, round-trip 3 lines through the duplex pipes. ──
  : ! ProcChild ProcessErr r1 ( process_spawn0 `cat` )
  ?? r1 {
    T child → {
      ( println `=== spawn cat ===` )
      ( print_int_line `pid_present` ? > ( proc_pid child ) 0 1 0 )

      ( proc_write_line child `alpha` )
      ( proc_write_line child `beta` )
      ( proc_write_line child `gamma` )
      ( proc_close_stdin child )

      ( read_one child `r1` )
      ( read_one child `r2` )
      ( read_one child `r3` )

      // After all 3 lines, next read should hit EOF.
      : ? String tail ( proc_read_line child 1000 )
      ?? tail {
        T s → { ( print_line `r4-unexpected` ( string_data s ) ) ( string_free s ) }
        F _ → {
          ? ( proc_eof child ) { ( println `r4=eof` ) } { ( println `r4=timeout` ) }
        }
      }

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

  // ── 2. Missing command — error path. ──────────────────────────────
  : ! ProcChild ProcessErr r2 ( process_spawn0 `nurl_does_not_exist_xyz_42` )
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

  // ── 3. Timeout path — `cat` doesn't reply on its own. ─────────────
  : ! ProcChild ProcessErr r3 ( process_spawn0 `cat` )
  ?? r3 {
    T child → {
      : ? String none1 ( proc_read_line child 100 )
      ?? none1 {
        T s → { ( print_line `r3-unexpected` ( string_data s ) ) ( string_free s ) }
        F _ → {
          ? ( proc_eof child ) { ( println `timeout=eof` ) } { ( println `timeout=ok` ) }
        }
      }
      // SIGTERM the child so the test exits promptly.
      ( proc_kill child 15 )
      : i ec ( proc_wait child )
      ( print_int_line `kill_exit` ec )
      ( proc_free child )
    }
    F _ → ( println `timeout-spawn-failed` )
  }

  ^ 0
}

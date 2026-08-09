// TEMPORARY diagnostic — delete before merging the macOS tier-1 work.
//
// Eleven corpus tests still fail on the macOS arm64 leg and every one of
// them reads from a child process: process_pipes, process_spawn_basic,
// mcp_stdio_basic hang outright, and net_loopback / http_server_seq come
// back with an empty client_out. The failing tests cannot say WHERE they
// stop, because the watchdog SIGKILLs them and stdio drops whatever was
// buffered — process_spawn_basic's very first header line never reached
// the log.
//
// So: markers, each flushed immediately, around progressively larger
// pieces of the path. Whichever marker is last in the log is the step
// that hung.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/process.nu`
$ `stdlib/core/posix.nu`

@ mark s m → v { ( nurl_print `[probe] ` ) ( nurl_print m ) ( nurl_print `\n` ) ( flush ) }

@ show s label ! Output ProcessErr r → v {
    ?? r {
        T o → {
            ( nurl_print `[probe] ` ) ( nurl_print label )
            ( nurl_print ` rc=` ) ( nurl_print ( nurl_str_int ( output_exit_code o ) ) )
            ( nurl_print ` out_len=` ) ( nurl_print ( nurl_str_int ( output_stdout_len o ) ) )
            ( nurl_print ` out=` ) ( nurl_print ( output_stdout o ) )
            ( nurl_print `\n` ) ( flush )
            ( output_free o )
        }
        F e → {
            ( nurl_print `[probe] ` ) ( nurl_print label )
            ( nurl_print ` ERR=` ) ( nurl_print ( nurl_str_int # i e ) ) ( nurl_print `\n` ) ( flush )
        }
    }
}

@ main → i {
    // Is the pure-NURL POSIX path even selected? process_run gates the
    // whole fork/exec/poll implementation on this being != -1.
    ( nurl_print `[probe] O_NONBLOCK=` )
    ( nurl_print ( nurl_str_int ( posix_const `O_NONBLOCK` ) ) )
    ( nurl_print ` POLLIN=` ) ( nurl_print ( nurl_str_int ( posix_const `POLLIN` ) ) )
    ( nurl_print ` POLLHUP=` ) ( nurl_print ( nurl_str_int ( posix_const `POLLHUP` ) ) )
    ( nurl_print ` F_GETFL=` ) ( nurl_print ( nurl_str_int ( posix_const `F_GETFL` ) ) )
    ( nurl_print `\n` ) ( flush )

    ( mark `A: before /bin/echo` )
    ( show `A /bin/echo` ( process_run1 `/bin/echo` `hi` ) )

    ( mark `B: before /usr/bin/true` )
    ( show `B true` ( process_run0 `/usr/bin/true` ) )

    ( mark `C: before PATH-resolved echo` )
    ( show `C echo` ( process_run1 `echo` `hi` ) )

    ( mark `D: before missing binary` )
    ( show `D missing` ( process_run0 `/nonexistent/nurl_probe_binary` ) )

    ( mark `E: before shell` )
    ( show `E shell` ( process_run_shell `printf abc` ) )

    ( mark `F: done` )
    ^ 0
}

// stdlib/std/process.nu — synchronous subprocess runner
//
// Wraps the runtime bridge in stdlib/runtime.c (§16). Blocks until the
// child exits, captures stdout + stderr in full, returns a typed Output
// or a ProcessErr describing what went wrong. Designed for the LLM
// agent-host use case: drive `git`, `npm`, `pytest`, `cargo`, …
// from NURL code and inspect the result with regular pattern matching.
//
// API (this revision):
//
//   ( process_run    s cmd ( Vec s ) args s stdin_str )
//                                                  → ! Output ProcessErr
//   ( process_run0   s cmd )                       → ! Output ProcessErr
//   ( process_run1   s cmd s a0 )                  → ! Output ProcessErr
//   ( process_run2   s cmd s a0 s a1 )             → ! Output ProcessErr
//   ( process_run3   s cmd s a0 s a1 s a2 )        → ! Output ProcessErr
//   ( process_run_shell s sh_cmd )                 → ! Output ProcessErr
//
//   ( output_exit_code Output o )                  → i
//   ( output_stdout    Output o )                  → s    BORROWED view
//   ( output_stderr    Output o )                  → s    BORROWED view
//   ( output_stdout_len Output o )                 → i
//   ( output_stderr_len Output o )                 → i
//   ( output_free      Output o )                  → v    early release (optional)
//   ( output_success   Output o )                  → b    exit_code == 0
//
//   ( process_err_name ProcessErr e )              → s    diagnostic
//
// Memory model — single-owner, LLM-friendly:
//
//   * Each call returns a fresh OWNED Output: it (with the stdout +
//     stderr buffers the runtime captured) is released when its last
//     owner goes — nothing to free by hand.
//   * `output_stdout` / `output_stderr` return BORROWED raw `s` views
//     (NUL-terminated). Do NOT free them; copy with `string_from` if
//     you need an owned `String` that outlives the Output.
//   * The `args` Vec is BORROWED — its element pointers must outlive
//     the call. When passing literal strings this is automatic; when
//     building from owned `String`s, push raw views with
//     `( vec_push [s] args ( string_data str ) )`.
//   * `cmd` and `stdin_str` are BORROWED — pass a literal or a
//     `( string_data str )` view. NULL-equivalent stdin is `\`\``.
//
// Errors — `ProcessErr` tags must mirror the runtime constants in
// stdlib/runtime.c §16 (NURL_PROC_ERR_*):
//
//   ProcessNotFound    1   cmd missing on PATH / file not found
//   ProcessExecFailed  2   fork/exec/CreateProcess failed otherwise
//   ProcessIo          3   pipe/wait/read failure mid-flight
//   ProcessOther       4   anything else / unsupported target (WASI)
//
// Platform notes:
//
//   * POSIX backend uses fork + execvp + poll(2) to multiplex
//     stdout/stderr drain — no deadlock on long output streams.
//   * Windows run/spawn launch native executables directly. A .bat/.cmd
//     command uses the system cmd.exe with automatic commands and delayed
//     expansion disabled; argv spaces, %, &, ! and = remain literal.
//     Batch arguments containing a double quote, CR or LF return an error;
//     these cannot represent the ordinary argv contract through cmd.exe.
//   * Win32 `process_run` uses CreateProcess + reader threads; the
//     duplex `process_spawn` family uses CreateProcess with an
//     OVERLAPPED named pipe for the child's stdout, which is what
//     makes `proc_read_line`'s timeout honourable there (an anonymous
//     pipe cannot be read with one). Both live in stdlib/runtime.c
//     §16/§16b. `cmd` is looked up via the standard PATH search; pass
//     an absolute path when in doubt.
//   * wasm32-wasi: every call returns ProcessOther.
//
// MVP scope — explicitly left for a follow-up:
//   - per-call timeout / cancellation
//   - streaming stdout/stderr (currently full-buffer capture)
//   - environment variable overrides for the child
//   - cwd override for the child

$ `stdlib/core/marker.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/core/rcbox.nu`
$ `stdlib/std/time.nu`

: | ProcessErr { ProcessNotFound ProcessExecFailed ProcessIo ProcessOther }

// A finished run: the exit code, the runtime's err_kind (0 when the
// child ran), and the captured stdout / stderr, each followed by one NUL
// (not counted in its length) so a text capture reads as a C string in
// place.
: ProcResult {
    i exit_code
    i err_kind
    ( Vec u ) out
    i out_len
    ( Vec u ) err
    i err_len
}

// Output holds a finished run in a counted block: every copy of an Output
// is the same result, and the last owner drops it — nothing to free by
// hand. Accessors below project into typed views.
: Output { ( Shared ProcResult ) raw }

@ Output_share Output h → Output { ^ @ Output { ( shared_clone [ProcResult] . h raw ) } }

@ Output_drop sink Output h → v {}

@ __output_res Output o → *ProcResult { ^ ( shared_ptr [ProcResult] . o raw ) }

// `n` bytes at `p`, then a NUL: a capture as a ProcResult keeps it.
@ __proc_capture s p i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] + n 1 )
    ? & > n 0 != # i p 0 {
        : *u bp # *u p
        : ~ i k 0
        ~ < k n { ( vec_push [u] v . bp k ) = k + k 1 }
    } {}
    ( vec_push [u] v # u 0 )
    ^ v
}

// A run that failed before it produced anything.
@ __proc_result_err i ek → ProcResult {
    ^ @ ProcResult { 0 ek ( __proc_capture `` 0 ) 0 ( __proc_capture `` 0 ) 0 }
}

// The runtime's C result block (Win32, WASI, the shell form there),
// released by the drop of its holder once it has been copied out.
// Sealed (`raw`): `res` is the runtime's result record its drop frees.
raw : __CProcResult { i res }

% Drop __CProcResult { @ drop __CProcResult c → v { ( nurl_proc_free . c res ) } }

@ __proc_result_from_c i raw → ProcResult {
    ? == raw 0 { ^ ( __proc_result_err 4 ) } {}
    : __CProcResult blk @ __CProcResult { raw }
    : i ol ( nurl_proc_stdout_len raw )
    : i el ( nurl_proc_stderr_len raw )
    ^ @ ProcResult { ( nurl_proc_exit_code raw ) ( nurl_proc_err_kind raw ) ( __proc_capture ( nurl_proc_stdout raw ) ol ) ol ( __proc_capture ( nurl_proc_stderr raw ) el ) el }
}

// Render a ProcessErr variant name as a raw `s`. Useful for log lines
// without a full match cascade at every call site.
@ process_err_name ProcessErr e → s {
    ^ ?? e {
        ProcessNotFound → `ProcessNotFound`
        ProcessExecFailed → `ProcessExecFailed`
        ProcessIo → `ProcessIo`
        ProcessOther → `ProcessOther`
    }
}

// Internal: classify the runtime err_kind into a ProcessErr variant.
@ __process_dispatch sink ProcResult r → !Output ProcessErr {
    : i ek . r err_kind
    ? != ek 0 {
        ? == ek 1 { ^ @ !Output ProcessErr { F # ProcessErr ProcessNotFound } } {}
        ? == ek 2 { ^ @ !Output ProcessErr { F # ProcessErr ProcessExecFailed } } {}
        ? == ek 3 { ^ @ !Output ProcessErr { F # ProcessErr ProcessIo } } {}
        ^ @ !Output ProcessErr { F # ProcessErr ProcessOther }
    } {}
    ^ @ !Output ProcessErr { T @ Output { ( shared_new [ProcResult] r ) } }
}

// ── PURIFY Phase 8 batch 2 — pure-NURL POSIX backend ────────────────
// Builds the ProcResult itself: the captures grow in Vecs and move into
// it. On Win32 / WASI the FFI symbols below (fork / pipe / execvp / poll
// / waitpid / fcntl) aren't available; `process_run` gates the whole
// pure-NURL path on `posix_const "O_NONBLOCK" != -1` and falls through
// to the runtime's C `nurl_proc_run` there.

// Read a little-endian i32 at byte offset `off` in `*u p`. Returns
// the value as a non-negative i for low values (we only use this on
// fds + errno which fit in 31 bits).
@ __le32_read * u p i off → i {
    : i b0 & 255 # i . p + off 0
    : i b1 & 255 # i . p + off 1
    : i b2 & 255 # i . p + off 2
    : i b3 & 255 # i . p + off 3
    ^ | | b0 << b1 8 | << b2 16 << b3 24
}

@ __le32_write * u p i off i val → v {
    = . p + off 0 # u & val 255
    = . p + off 1 # u & >> val 8 255
    = . p + off 2 # u & >> val 16 255
    = . p + off 3 # u & >> val 24 255
}

// Read fd[0] (read end) or fd[1] (write end) from a pipe(2) output
// buffer. The buffer is two contiguous native ints (4 bytes each on
// every supported target).
@ __pipe_fd s pipe_buf i which → i {
    : *u p # *u pipe_buf
    ^ ( __le32_read p * which 4 )
}

@ __set_nonblock i fd → v {
    : i fl ( fcntl fd ( posix_const `F_GETFL` ) 0 )
    ? != fl -1 {
        ( fcntl fd ( posix_const `F_SETFL` ) | fl ( posix_const `O_NONBLOCK` ) )
    } {}
}

@ __set_cloexec i fd → v {
    : i fl ( fcntl fd ( posix_const `F_GETFD` ) 0 )
    ? != fl -1 {
        ( fcntl fd ( posix_const `F_SETFD` ) | fl ( posix_const `FD_CLOEXEC` ) )
    } {}
}

// Build a NULL-terminated argv array: [cmd, args..., NULL], the words of
// a Vec the caller holds while execvp reads `vec_data` (the child of a
// fork has its own copy).
@ __build_argv s cmd ( Vec s ) args → ( Vec i ) {
    : i argc ( vec_len [s] args )
    : ( Vec i ) argv ( vec_zeroed [i] + argc 2 )
    : s full # s ( vec_data [i] argv )
    : *u cmd_p # *u cmd
    ( nurl_poke full 0 # i cmd_p )
    : ~ i i 0
    ~ < i argc {
        : ?s ai ( vec_get [s] args i )
        ?? ai {
            T sv → { ( nurl_poke full + i 1 # i # *u sv ) }
            F _ → { : *u empty_p # *u `` ( nurl_poke full + i 1 # i empty_p ) }
        }
        = i + i 1
    }
    ( nurl_poke full + argc 1 0 )
    ^ argv
}

// Drain a non-blocking fd onto `buf`. Returns -1 on EOF or hard error
// (caller closes the fd), 0 on EAGAIN (more data later). `iov`'s first
// 4 KiB are the read chunk.
@ __pb_drain_fd i fd ( Vec u ) buf ( Vec u ) iov → i {
    ~ T {
        : i rd ( read fd ( vec_data [u] iov ) 4096 )
        ? > rd 0 {
            ( vec_extend_range [u] buf iov 0 rd )
        } {
            ? == rd 0 { ^ -1 } {}
            : i e ( nurl_errno_get )
            ? == e ( posix_const `EINTR` ) {} {
                ? == e ( posix_const `EAGAIN` ) { ^ 0 } {}
                ? == e ( posix_const `EWOULDBLOCK` ) { ^ 0 } {}
                ^ -1
            }
        }
    }
    ^ 0
}

// Read the exec-error sideband — child wrote 4 bytes (errno as LE)
// only if execvp failed; EOF without bytes ⇒ exec succeeded. errno is
// always > 0 on POSIX, so a decoded value of 0 unambiguously means
// "no bytes / exec succeeded".
@ __read_exec_errno i fd → i {
    : ( Vec i ) bv ( vec_zeroed [i] 1 )
    : *u up # *u ( vec_data [i] bv )
    : ~ i got 0
    : ~ i done 0
    ~ == done 0 {
        ? >= got 4 { = done 1 } {
            : s slice # s + # i up got
            : i rd ( read fd # *u slice - 4 got )
            ? > rd 0 { = got + got rd } {
                ? == rd 0 { = done 1 } {
                    : i e ( nurl_errno_get )
                    ? == e ( posix_const `EINTR` ) {} { = done 1 }
                }
            }
        }
    }
    ^ ( __le32_read up 0 )
}

// Write the child's errno to the exec-error sideband. Best-effort.
@ __write_exec_errno i fd i errno_val → v {
    : ( Vec i ) bv ( vec_zeroed [i] 1 )
    : *u up # *u ( vec_data [i] bv )
    ( __le32_write up 0 errno_val )
    ( write fd up 4 )
}

// Map a child-side exec errno to NurlProcResult err_kind.
@ __map_exec_errno i e → i {
    ? == e ( posix_const `ENOENT` ) { ^ 1 } {}  // NotFound
    ^ 2  // ExecFailed
}

// Decode waitpid status (raw int) into a (exit_code, err_kind) pair.
@ __decode_status i raw_status i io_err i child_errno inout i code inout i ek → v {
    ? != child_errno 0 {
        = code -1
        = ek ( __map_exec_errno child_errno )
    } { ? != io_err 0 {
            = code -1
            = ek 3  // Io
        } { ? == ( nurl_wait_is_exited raw_status ) 1 {
                = code ( nurl_wait_exit_status raw_status )
                = ek 0  // ok
            } { ? == ( nurl_wait_is_signaled raw_status ) 1 {
                    = code + 128 ( nurl_wait_term_sig raw_status )
                    = ek 0  // ok
                } {
                    = code -1
                    = ek 4  // Other
                } } } }
}

// Main entry — translated step-by-step from runtime.c §16
// `nurl_proc_run` POSIX backend.
@ __process_run_posix s cmd ( Vec s ) args s stdin_str → !Output ProcessErr {
    : i cmd_len ( nurl_str_len cmd )
    ? <= cmd_len 0 {
        ^ ( __process_dispatch ( __proc_result_err 1 ) )  // NotFound
    } {}

    // Four 2-int pipe buffers, 8 bytes each in one zeroed Vec. fd values
    // land at offsets 0 + 4 of each.
    : ( Vec i ) pipev ( vec_zeroed [i] 4 )
    : s sin_p # s ( vec_data [i] pipev )
    : s sout_p # s + # i sin_p 8
    : s serr_p # s + # i sin_p 16
    : s err_p # s + # i sin_p 24

    : i p1 ( pipe # *u sin_p )
    : i p2 ( pipe # *u sout_p )
    : i p3 ( pipe # *u serr_p )
    : i p4 ( pipe # *u err_p )
    ? || || < p1 0 < p2 0 || < p3 0 < p4 0 {
        // Clean up any pipes that did open. -1 means never opened.
        ? >= p1 0 {
            ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        } {}
        ? >= p2 0 {
            ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        } {}
        ? >= p3 0 {
            ( close ( __pipe_fd serr_p 0 ) ) ( close ( __pipe_fd serr_p 1 ) )
        } {}
        ? >= p4 0 {
            ( close ( __pipe_fd err_p 0 ) ) ( close ( __pipe_fd err_p 1 ) )
        } {}
        ^ ( __process_dispatch ( __proc_result_err 3 ) )  // Io
    } {}

    // CLOEXEC on err_p[1] so a successful exec triggers EOF on read.
    ( __set_cloexec ( __pipe_fd err_p 1 ) )

    : ( Vec i ) argv ( __build_argv cmd args )

    // stdout is block-buffered when it is a pipe or a file, so anything
    // the parent has printed but not yet written out would be inherited
    // by the child's copy of the buffer and emitted TWICE. Drain it
    // before the fork — the standard pre-fork discipline.
    ( nurl_flush_stdout )
    : i pid ( fork )
    ? < pid 0 {
        ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        ( close ( __pipe_fd serr_p 0 ) ) ( close ( __pipe_fd serr_p 1 ) )
        ( close ( __pipe_fd err_p 0 ) ) ( close ( __pipe_fd err_p 1 ) )
        ^ ( __process_dispatch ( __proc_result_err 3 ) )  // Io
    } {}

    ? == pid 0 {
        // Child: dup2 child-side ends onto std{in,out,err}, then close
        // every original pipe end (including the read end of the
        // exec-error sideband). Finally execvp; on failure write errno
        // to the sideband and _exit(127).
        ( dup2 ( __pipe_fd sin_p 0 ) 0 )
        ( dup2 ( __pipe_fd sout_p 1 ) 1 )
        ( dup2 ( __pipe_fd serr_p 1 ) 2 )
        ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        ( close ( __pipe_fd serr_p 0 ) ) ( close ( __pipe_fd serr_p 1 ) )
        ( close ( __pipe_fd err_p 0 ) )
        ( execvp cmd # *u ( vec_data [i] argv ) )
        : i e ( nurl_errno_get )
        ( __write_exec_errno ( __pipe_fd err_p 1 ) e )
        ( _exit 127 )
    } {}

    // Close child-side pipe ends.
    ( close ( __pipe_fd sin_p 0 ) )
    ( close ( __pipe_fd sout_p 1 ) )
    ( close ( __pipe_fd serr_p 1 ) )
    ( close ( __pipe_fd err_p 1 ) )

    : i sin_wfd ( __pipe_fd sin_p 1 )
    : i sout_rfd ( __pipe_fd sout_p 0 )
    : i serr_rfd ( __pipe_fd serr_p 0 )
    : i err_rfd ( __pipe_fd err_p 0 )

    ( __set_nonblock sout_rfd )
    ( __set_nonblock serr_rfd )

    // Ignore SIGPIPE locally so an early-exiting child doesn't crash
    // the parent on the stdin write.
    : *u old_pipe ( signal ( posix_const `SIGPIPE` ) # *u ( posix_const `SIG_IGN` ) )
    : i stdin_len ( nurl_str_len stdin_str )
    ? > stdin_len 0 {
        : ~ i off 0
        ~ < off stdin_len {
            : s slice # s + # i # *u stdin_str off
            : i wr ( write sin_wfd # *u slice - stdin_len off )
            ? > wr 0 {
                = off + off wr
            } {
                ? < wr 0 {
                    : i e ( nurl_errno_get )
                    ? == e ( posix_const `EINTR` ) {} { = off stdin_len }
                } { = off stdin_len }
            }
        }
    } {}
    ( close sin_wfd )
    ( signal ( posix_const `SIGPIPE` ) old_pipe )

    // Drain stdout + stderr in a poll loop until both report EOF.
    : ( Vec u ) outb ( vec_with_cap [u] 256 )
    : ( Vec u ) errb ( vec_with_cap [u] 256 )
    // A 4 KiB read buffer and two pollfd entries, in one Vec.
    : ( Vec u ) iov ( vec_zeroed [u] 4112 )
    : s pollfds # s + # i ( vec_data [u] iov ) 4096
    : ~ i out_open 1
    : ~ i err_open 1
    : ~ i io_err 0
    : i pollin ( posix_const `POLLIN` )
    ~ || == out_open 1 == err_open 1 {
        : ~ i n 0
        ? == out_open 1 {
            ( posix_pollfd_set # *u pollfds * n 8 sout_rfd pollin )
            = n + n 1
        } {}
        ? == err_open 1 {
            ( posix_pollfd_set # *u pollfds * n 8 serr_rfd pollin )
            = n + n 1
        } {}
        : i pr ( poll # *u pollfds n -1 )
        ? < pr 0 {
            : i pe ( nurl_errno_get )
            ? == pe ( posix_const `EINTR` ) {} {
                = io_err 1
                = out_open 0
                = err_open 0
            }
        } {
            : ~ i k 0
            ~ < k n {
                : i off * k 8
                : i rev ( posix_pollfd_revents # *u pollfds off )
                ? != rev 0 {
                    : i fd ( __le32_read # *u pollfds off )
                    : i drain_rc ? == fd sout_rfd ( __pb_drain_fd fd outb iov ) ( __pb_drain_fd fd errb iov )
                    : i hup_or_err & rev | ( posix_const `POLLHUP` ) ( posix_const `POLLERR` )
                    ? || == drain_rc -1 != hup_or_err 0 {
                        ? == fd sout_rfd { = out_open 0 } { = err_open 0 }
                    } {}
                } {}
                = k + k 1
            }
        }
    }

    ( close sout_rfd )
    ( close serr_rfd )

    : i child_errno ( __read_exec_errno err_rfd )
    ( close err_rfd )

    // waitpid with EINTR retry.
    : ( Vec i ) status_v ( vec_zeroed [i] 1 )
    : *u status_p # *u ( vec_data [i] status_v )
    : ~ i w 0
    : ~ i wait_done 0
    ~ == wait_done 0 {
        = w ( waitpid pid status_p 0 )
        ? >= w 0 { = wait_done 1 } {
            : i we ( nurl_errno_get )
            ? == we ( posix_const `EINTR` ) {} { = wait_done 1 = io_err 1 }
        }
    }
    : i raw_status ( __le32_read status_p 0 )

    : ~ i code 0
    : ~ i ek 0
    ( __decode_status raw_status io_err child_errno code ek )

    // The captures move into the result, each with its NUL.
    : i out_len ( vec_len [u] outb )
    : i err_len ( vec_len [u] errb )
    ( vec_push [u] outb # u 0 )
    ( vec_push [u] errb # u 0 )
    ^ ( __process_dispatch @ ProcResult { code ek outb out_len errb err_len } )
}

// Core entry point. `args` carries argv[1..]; argv[0] is `cmd` itself.
// `stdin_str` may be `` to send empty stdin.
//
// On POSIX (Linux / macOS) `__process_run_posix` handles the call in
// pure NURL. Win32 / WASI fall through to the C `nurl_proc_run` since
// the POSIX FFI primitives don't exist there.
@ process_run s cmd ( Vec s ) args s stdin_str → !Output ProcessErr {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __process_run_posix cmd args stdin_str )
    } {}
    : *s argv ( vec_data [s] args )
    : i argc ( vec_len [s] args )
    : s argv_buf # s argv
    ^ ( __process_dispatch ( __proc_result_from_c ( nurl_proc_run cmd argv_buf argc stdin_str ) ) )
}

// …with the arguments as Strings the caller owns — an argv built in a
// loop (numbers, paths, a variable count): they outlive the call, so the
// argv handed on is views of them, and nothing is copied or kept.
@ process_run_strings s cmd ( Vec String ) args s stdin_str → !Output ProcessErr {
    : i n ( vec_len [String] args )
    : ( Vec s ) av ( vec_with_cap [s] n )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] args k ) { T a → ( vec_push [s] av ( string_data a ) ) F → {} }
        = k + k 1
    }
    : !Output ProcessErr res ( process_run cmd av stdin_str )
    ^ res
}

// ── Convenience arities ────────────────────────────────────────────

@ process_run0 s cmd → !Output ProcessErr {
    : ( Vec s ) args ( vec_new [s] )
    : !Output ProcessErr res ( process_run cmd args `` )
    ^ res
}

@ process_run1 s cmd s a0 → !Output ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 1 )
    ( vec_push [s] args a0 )
    : !Output ProcessErr res ( process_run cmd args `` )
    ^ res
}

@ process_run2 s cmd s a0 s a1 → !Output ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 2 )
    ( vec_push [s] args a0 )
    ( vec_push [s] args a1 )
    : !Output ProcessErr res ( process_run cmd args `` )
    ^ res
}

@ process_run3 s cmd s a0 s a1 s a2 → !Output ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 3 )
    ( vec_push [s] args a0 )
    ( vec_push [s] args a1 )
    ( vec_push [s] args a2 )
    : !Output ProcessErr res ( process_run cmd args `` )
    ^ res
}

// Run a shell pipeline via /bin/sh -c (or cmd.exe /c on Windows).
// Convenient for one-liners with quoting / redirection / pipes that
// would otherwise need awkward argv handling.
& `c` @ nurl_proc_run_shell s command → i

@ process_run_shell s sh_cmd → !Output ProcessErr {
    ? == ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __process_dispatch ( __proc_result_from_c ( nurl_proc_run_shell sh_cmd ) ) )
    } {}
    : ( Vec s ) args ( vec_with_cap [s] 2 )
    ( vec_push [s] args `-c` )
    ( vec_push [s] args sh_cmd )
    : !Output ProcessErr res ( process_run `/bin/sh` args `` )
    ^ res
}

// ── Accessors (borrowed views into the Output's own buffers) ───────

@ output_exit_code Output o → i { ^ . ( __output_res o ) exit_code }

@ output_stdout Output o → s { ^ # s ( vec_data [u] . ( __output_res o ) out ) }

@ output_stderr Output o → s { ^ # s ( vec_data [u] . ( __output_res o ) err ) }

@ output_stdout_len Output o → i { ^ . ( __output_res o ) out_len }

@ output_stderr_len Output o → i { ^ . ( __output_res o ) err_len }

@ output_success Output o → b {
    ^ == 0 ( output_exit_code o )
}

// Let go of `o` now rather than at the end of its owner's scope.
@ output_free sink Output o → v {}

// ─────────────────────────────────────────────────────────────────────
// Duplex stdio child — long-lived process with live stdin / stdout
// pipes. Stderr is INHERITED from the parent (matches MCP convention:
// servers log diagnostics there and the parent forwards to terminal).
//
// API:
//
//   ( process_spawn s cmd ( Vec s ) args )      → ! ProcChild ProcessErr
//   ( process_spawn0 s cmd )                    → ! ProcChild ProcessErr
//   ( process_spawn1 s cmd s a0 )               → ! ProcChild ProcessErr
//   ( process_spawn2 s cmd s a0 s a1 )          → ! ProcChild ProcessErr
//
//   ( proc_pid          ProcChild p )           → i
//   ( proc_write        ProcChild p *u buf i n ) → i     bytes written, -1 err;
//                                                        `unsafe` callers only
//   ( proc_write_str    ProcChild p s s_view )  → i
//   ( proc_write_bytes  ProcChild p ( Vec u ) data ) → i  full-write loop
//   ( proc_write_line   ProcChild p s line )    → i      appends '\n'
//   ( proc_close_stdin  ProcChild p )           → v
//
//   ( proc_read_line    ProcChild p i timeout_ms )
//                                              → ? String   None on timeout/EOF
//   ( proc_read_chunk   ProcChild p i max )
//                                              → ! ( Vec u ) ProcessErr
//                                                 blocking raw read; empty = EOF
//   ( proc_eof          ProcChild p )           → b
//   ( proc_last_io_err  ProcChild p )           → i      raw errno
//
//   ( proc_wait         ProcChild p )           → i      blocks
//   ( proc_kill         ProcChild p i sig )     → i      0 ok / -1 err
//   ( proc_free         ProcChild p )           → v      early release (optional)
//
// Memory model:
//   * A ProcChild releases itself: every copy of it (a struct field, a
//     Vec element, a closure capture, `ProcChild_share`) is the same
//     child, and when its last owner goes the child is shut down —
//     stdin/stdout closed, an unwaited child SIGTERMed (then SIGKILLed),
//     reaped with waitpid, the handle freed. A child `proc_wait` already
//     reaped is not signalled. Nothing to free by hand; `proc_free` lets
//     go of one owner early.
//   * `proc_read_line` returns a freshly-OWNED `String` on Some. None
//     means timeout (peer still alive, `proc_eof` = false) OR EOF (peer
//     closed, `proc_eof` = true).
//   * `proc_read_chunk` returns a freshly-OWNED `( Vec u )` on Ok. It
//     BLOCKS until the child produces bytes (one read(2)-worth, at most
//     `max`); an EMPTY Vec means EOF (child closed stdout). Bytes already
//     buffered by a previous `proc_read_line` call are served first, so
//     the two read styles interleave safely. POSIX only — Win32/WASI
//     return ProcessOther (use `proc_read_line` there).
//   * Args Vec is BORROWED — element pointers must outlive the spawn call.

// A child: its pid, pipe ends and read buffers. The pure-NURL POSIX
// backend keeps all of it here; on Win32 / WASI `craw` is the runtime's C
// block (NurlProcChild, stdlib/runtime.c §16b) and the rest goes unused.
// Sealed (`raw`): `craw` is the runtime's child record its drop frees,
// and `pid` the process it signals.
raw : ProcChildImpl {
    i craw
    i err_kind  // 0 / NURL_PROC_ERR_*
    i last_io_err  // errno snapshot
    i exit_code  // -1 until wait succeeds
    i eof
    i waited
    i pid
    i fd_in  // -1 once closed
    i fd_out  // -1 once closed
    ( Vec u ) scratch  // bytes read, not yet handed out
    ( Vec u ) line  // the most recent line, then a NUL
    ( Vec u ) io  // poll entry (8 bytes) + read chunk (4 KiB), made on the first read
}

// The child's shutdown, run by its last owner: close the pipes, stop and
// reap a child nobody waited for. The buffers go with the fields.
% Drop ProcChildImpl {
    @ drop ProcChildImpl x → v {
        ? != ( posix_const `O_NONBLOCK` ) -1 {
            ? >= . x fd_in 0 { ( close . x fd_in ) } {}
            ? >= . x fd_out 0 { ( close . x fd_out ) } {}
            ( __proc_reap_posix . x pid . x waited )
        } {
            ? != . x craw 0 { ( nurl_proc_spawn_free . x craw ) } {}
        }
    }
}

: ProcChild { ( Shared ProcChildImpl ) raw }

// Its drop closes something the outside world sees (stdlib/core/marker.nu).
% Resource ProcChild {}

@ ProcChild_share ProcChild h → ProcChild { ^ @ ProcChild { ( shared_clone [ProcChildImpl] . h raw ) } }

@ ProcChild_drop sink ProcChild h → v {}

@ __proc_st ProcChild p → *ProcChildImpl { ^ ( shared_ptr [ProcChildImpl] . p raw ) }

@ __proc_raw ProcChild p → i { ^ . ( __proc_st p ) craw }

// A child with nothing started yet: `ek` / `errno` say why (0 when it is
// about to be filled in).
@ __pc_new i craw i ek i errno → ProcChildImpl {
    ^ @ ProcChildImpl { craw ek errno -1 0 0 0 -1 -1 ( vec_new [u] ) ( vec_new [u] ) ( vec_new [u] ) }
}

@ __proc_spawn_dispatch sink ProcChildImpl c → !ProcChild ProcessErr {
    : i ek . c err_kind
    // Owned from here: an error drops it with `p` (a failed spawn has no
    // pid and no open pipe, so that only releases it).
    : ProcChild p @ ProcChild { ( shared_new [ProcChildImpl] c ) }
    ? != ek 0 {
        ? == ek 1 { ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessNotFound } } {}
        ? == ek 2 { ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessExecFailed } } {}
        ? == ek 3 { ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessIo } } {}
        ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessOther }
    } {}
    ^ @ !ProcChild ProcessErr { T p }
}

// A child the C runtime started (Win32 / WASI): its block, and its
// err_kind (Other when there is no block at all).
@ __pc_from_c i raw → ProcChildImpl {
    ? == raw 0 { ^ ( __pc_new 0 4 0 ) } {}
    ^ ( __pc_new raw ( nurl_proc_spawn_err_kind raw ) 0 )
}

// ── PURIFY Phase 8 batch 3 — pure-NURL POSIX spawn backend ─────────

// The read paths' poll(2) entry (8 bytes) and read(2) chunk (4 KiB): one
// buffer per child, made on the first read.
@ __pc_io * ProcChildImpl c → s {
    ? == ( vec_len [u] . c io ) 0 { = . c io ( vec_zeroed [u] 4104 ) } {}
    ^ # s ( vec_data [u] . c io )
}

// line := the `n` bytes at `p`, then a NUL (its buffer reused).
@ __pc_set_line * ProcChildImpl c * u p i n → v {
    ( vec_clear [u] . c line )
    : ~ i k 0
    ~ < k n { ( vec_push [u] . c line . p k ) = k + k 1 }
    ( vec_push [u] . c line # u 0 )
}

// The line just read, as a view valid until the next read ("" if none).
@ __pc_line_view * ProcChildImpl c → s {
    ? == ( vec_len [u] . c line ) 0 { ^ `` } {}
    ^ # s ( vec_data [u] . c line )
}

// Drop the first `k` bytes of scratch (the tail moves down; the two
// ranges overlap, so memmove).
@ __pc_consume * ProcChildImpl c i k → v {
    : i rem - ( vec_len [u] . c scratch ) k
    ? > rem 0 {
        : *u base ( vec_data [u] . c scratch )
        : *u tail # *u + # i base k
        ( nurl_memmove base tail rem )
    } {}
    : b _t ( vec_truncate [u] . c scratch ? > rem 0 rem 0 )
}

// Try to extract the first '\n'-terminated line from scratch into the
// line buffer. Returns 1 on success. The trailing '\n' is consumed but not
// copied; an optional '\r' before it is also stripped.
@ __pc_drain_line * ProcChildImpl c → i {
    : i n ( vec_len [u] . c scratch )
    ? == n 0 { ^ 0 } {}
    : *u sp ( vec_data [u] . c scratch )
    : ~ i i 0
    ~ < i n {
        ? == & 255 # i . sp i 10 {  // '\n'
            : ~ i take i
            ? > take 0 {
                ? == & 255 # i . sp - take 1 13 { = take - take 1 } {}  // '\r'
            } {}
            ( __pc_set_line c sp take )
            ( __pc_consume c + i 1 )
            ^ 1
        } {}
        = i + i 1
    }
    ^ 0
}

// What is left in scratch at EOF, without a trailing '\n', becomes the line.
@ __pc_flush_tail * ProcChildImpl c → s {
    : i sc_len ( vec_len [u] . c scratch )
    ? > sc_len 0 {
        ( __pc_set_line c ( vec_data [u] . c scratch ) sc_len )
        ( vec_clear [u] . c scratch )
        ^ ( __pc_line_view c )
    } {}
    ^ ``
}

@ __process_spawn_posix s cmd ( Vec s ) args → !ProcChild ProcessErr {
    : i cmd_len ( nurl_str_len cmd )
    ? <= cmd_len 0 {
        ^ ( __proc_spawn_dispatch ( __pc_new 0 1 0 ) )  // NotFound
    } {}

    // Three 2-int pipe buffers, 8 bytes each in one zeroed Vec.
    : ( Vec i ) pipev ( vec_zeroed [i] 3 )
    : s sin_p # s ( vec_data [i] pipev )
    : s sout_p # s + # i sin_p 8
    : s err_p # s + # i sin_p 16

    : i p1 ( pipe # *u sin_p )
    : i p2 ( pipe # *u sout_p )
    : i p3 ( pipe # *u err_p )
    ? || || < p1 0 < p2 0 < p3 0 {
        ? >= p1 0 {
            ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        } {}
        ? >= p2 0 {
            ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        } {}
        ? >= p3 0 {
            ( close ( __pipe_fd err_p 0 ) ) ( close ( __pipe_fd err_p 1 ) )
        } {}
        ^ ( __proc_spawn_dispatch ( __pc_new 0 3 ( nurl_errno_get ) ) )  // Io
    } {}

    ( __set_cloexec ( __pipe_fd err_p 1 ) )

    : ( Vec i ) argv ( __build_argv cmd args )

    // See the fork in __process_run: drain the parent's pending stdout
    // so the child cannot re-emit it.
    ( nurl_flush_stdout )
    : i pid ( fork )
    ? < pid 0 {
        ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        ( close ( __pipe_fd err_p 0 ) ) ( close ( __pipe_fd err_p 1 ) )
        ^ ( __proc_spawn_dispatch ( __pc_new 0 3 ( nurl_errno_get ) ) )  // Io
    } {}

    ? == pid 0 {
        ( dup2 ( __pipe_fd sin_p 0 ) 0 )
        ( dup2 ( __pipe_fd sout_p 1 ) 1 )
        // stderr inherits — no dup
        ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        ( close ( __pipe_fd err_p 0 ) )
        ( execvp cmd # *u ( vec_data [i] argv ) )
        : i e ( nurl_errno_get )
        ( __write_exec_errno ( __pipe_fd err_p 1 ) e )
        ( _exit 127 )
    } {}
    ( close ( __pipe_fd sin_p 0 ) )
    ( close ( __pipe_fd sout_p 1 ) )
    ( close ( __pipe_fd err_p 1 ) )

    : i sin_wfd ( __pipe_fd sin_p 1 )
    : i sout_rfd ( __pipe_fd sout_p 0 )
    : i err_rfd ( __pipe_fd err_p 0 )

    : i child_errno ( __read_exec_errno err_rfd )
    ( close err_rfd )
    ? != child_errno 0 {
        ( close sin_wfd ) ( close sout_rfd )
        : ( Vec i ) status_v ( vec_zeroed [i] 1 )
        : *u status_p # *u ( vec_data [i] status_v )
        ( waitpid pid status_p 0 )
        ^ ( __proc_spawn_dispatch ( __pc_new 0 ( __map_exec_errno child_errno ) child_errno ) )
    } {}

    // Non-blocking on stdout so timeout-driven read_line doesn't wedge.
    ( __set_nonblock sout_rfd )

    : ProcChildImpl c ( __pc_new 0 0 0 )
    = . c pid pid
    = . c fd_in sin_wfd
    = . c fd_out sout_rfd
    ^ ( __proc_spawn_dispatch c )
}

@ __proc_write_posix * ProcChildImpl c s buf i n → i {
    : i fd_in . c fd_in
    ? < fd_in 0 { ^ 0 } {}
    ? <= n 0 { ^ 0 } {}
    : *u old_pipe ( signal ( posix_const `SIGPIPE` ) # *u ( posix_const `SIG_IGN` ) )
    : ~ i total 0
    ~ < total n {
        : s slice # s + # i # *u buf total
        : i w ( write fd_in # *u slice - n total )
        ? > w 0 { = total + total w } {
            ? < w 0 {
                : i e ( nurl_errno_get )
                ? == e ( posix_const `EINTR` ) {} {
                    = . c last_io_err e
                    ( signal ( posix_const `SIGPIPE` ) old_pipe )
                    ^ -1
                }
            } { = total n }  // w == 0: break
        }
    }
    ( signal ( posix_const `SIGPIPE` ) old_pipe )
    ^ total
}

@ __proc_close_stdin_posix * ProcChildImpl c → v {
    ? >= . c fd_in 0 {
        ( close . c fd_in )
        = . c fd_in -1
    } {}
}

// Read one line (see proc_read_line); a view of the line buffer.
@ __proc_read_line_posix * ProcChildImpl c i timeout_ms → s {
    // Reset the previous line.
    ( vec_clear [u] . c line )

    ? == 1 ( __pc_drain_line c ) { ^ ( __pc_line_view c ) } {}

    : i fd_out . c fd_out
    ? < fd_out 0 {
        = . c eof 1
        ^ ``
    } {}

    : s pollfds ( __pc_io c )
    : *u chunk # *u + # i pollfds 8
    : i pollin ( posix_const `POLLIN` )
    : i pollhup ( posix_const `POLLHUP` )
    : i pollerr ( posix_const `POLLERR` )

    ~ T {
        ( posix_pollfd_set # *u pollfds 0 fd_out pollin )
        : i wait_for ? > timeout_ms 0 timeout_ms -1
        : ~ i pr 0
        : ~ i poll_done 0
        ~ == poll_done 0 {
            = pr ( poll # *u pollfds 1 wait_for )
            ? >= pr 0 { = poll_done 1 } {
                : i pe ( nurl_errno_get )
                ? != pe ( posix_const `EINTR` ) { = poll_done 1 } {}
            }
        }
        ? == pr 0 {
            ^ ``  // timeout
        } {}
        ? < pr 0 {
            = . c err_kind 3  // Io
            = . c last_io_err ( nurl_errno_get )
            ^ ``
        } {}
        : i rev ( posix_pollfd_revents # *u pollfds 0 )
        ? != & rev pollin 0 {
            // Drain everything currently buffered.
            : ~ i drain_done 0
            ~ == drain_done 0 {
                : i rd ( read fd_out chunk 4096 )
                ? > rd 0 {
                    ( vec_extend_range [u] . c scratch . c io 8 rd )
                } {
                    ? == rd 0 {
                        ( close fd_out )
                        = . c fd_out -1
                        = . c eof 1
                        = drain_done 1
                    } {
                        : i re ( nurl_errno_get )
                        ? == re ( posix_const `EINTR` ) {} {
                            ? == re ( posix_const `EAGAIN` ) { = drain_done 1 } {
                                ? == re ( posix_const `EWOULDBLOCK` ) { = drain_done 1 } {
                                    = . c err_kind 3
                                    = . c last_io_err re
                                    ^ ``
                                }
                            }
                        }
                    }
                }
            }
            ? == 1 ( __pc_drain_line c ) { ^ ( __pc_line_view c ) } {}
            // EOF without trailing '\n': flush tail.
            ? != . c eof 0 { ^ ( __pc_flush_tail c ) } {}
        } {}
        ? != & rev | pollhup pollerr 0 {
            ( close fd_out )
            = . c fd_out -1
            = . c eof 1
            ? == 1 ( __pc_drain_line c ) { ^ ( __pc_line_view c ) } {}
            ^ ( __pc_flush_tail c )
        } {}
        // Loop — still no '\n' yet.
    }
    ^ ``
}

// Blocking raw-byte read from the child's stdout. Serves any bytes
// left in the read_line scratch buffer first, then poll(2)s (infinite
// timeout — the fd is O_NONBLOCK, poll gates the read) and does one
// read(2) of at most `max` bytes. Empty Vec ⇒ EOF.
@ __proc_read_chunk_posix * ProcChildImpl c i max → !( Vec u ) ProcessErr {
    ? <= max 0 { ^ @ !( Vec u ) ProcessErr { T ( vec_new [u] ) } } {}

    // 1. Drain bytes buffered by an earlier proc_read_line call.
    : i sc_len ( vec_len [u] . c scratch )
    ? > sc_len 0 {
        : i take ? > sc_len max max sc_len
        : ( Vec u ) buf ( vec_with_cap [u] take )
        ( vec_extend_range [u] buf . c scratch 0 take )
        ( __pc_consume c take )
        ^ @ !( Vec u ) ProcessErr { T buf }
    } {}

    : i fd_out . c fd_out
    ? < fd_out 0 {
        = . c eof 1
        ^ @ !( Vec u ) ProcessErr { T ( vec_new [u] ) }
    } {}

    : s pollfds ( __pc_io c )
    : i pollin ( posix_const `POLLIN` )
    ~ T {
        // 2. Block until readable or HUP; EINTR retries.
        ( posix_pollfd_set # *u pollfds 0 fd_out pollin )
        : ~ i pr -1
        : ~ i poll_done 0
        ~ == poll_done 0 {
            = pr ( poll # *u pollfds 1 -1 )
            ? >= pr 0 { = poll_done 1 } {
                : i pe ( nurl_errno_get )
                ? != pe ( posix_const `EINTR` ) { = poll_done 1 } {}
            }
        }
        ? < pr 0 {
            = . c err_kind 3  // Io
            = . c last_io_err ( nurl_errno_get )
            ^ @ !( Vec u ) ProcessErr { F # ProcessErr ProcessIo }
        } {}
        // 3. One read(2) — POLLIN and POLLHUP both resolve here.
        : ( Vec u ) buf ( vec_with_cap [u] max )
        : *u dst ( vec_data [u] buf )
        : i rd ( read fd_out dst max )
        ? > rd 0 {
            : b _ok ( vec_set_len [u] buf rd )
            ^ @ !( Vec u ) ProcessErr { T buf }
        } {}
        ? == rd 0 {
            ( close fd_out )
            = . c fd_out -1
            = . c eof 1
            ^ @ !( Vec u ) ProcessErr { T buf }  // empty ⇒ EOF
        } {}
        : i re ( nurl_errno_get )
        ? == re ( posix_const `EINTR` ) {} {
            ? || == re ( posix_const `EAGAIN` ) == re ( posix_const `EWOULDBLOCK` ) {} {
                = . c err_kind 3  // Io
                = . c last_io_err re
                ^ @ !( Vec u ) ProcessErr { F # ProcessErr ProcessIo }
            }
        }
        // EINTR / spurious EAGAIN: poll again.
    }
    ^ @ !( Vec u ) ProcessErr { T ( vec_new [u] ) }
}

@ __proc_wait_posix * ProcChildImpl c → i {
    ? != . c waited 0 { ^ . c exit_code } {}
    : i pid . c pid
    ? <= pid 0 { ^ -1 } {}
    : ( Vec i ) status_v ( vec_zeroed [i] 1 )
    : *u status_p # *u ( vec_data [i] status_v )
    : ~ i w 0
    : ~ i wait_done 0
    ~ == wait_done 0 {
        = w ( waitpid pid status_p 0 )
        ? >= w 0 { = wait_done 1 } {
            : i e ( nurl_errno_get )
            ? != e ( posix_const `EINTR` ) {
                = wait_done 1
                = . c last_io_err e
                ^ -1
            } {}
        }
    }
    : i raw_status ( __le32_read status_p 0 )
    : ~ i ec -1
    ? == 1 ( nurl_wait_is_exited raw_status ) {
        = ec ( nurl_wait_exit_status raw_status )
    } {
        ? == 1 ( nurl_wait_is_signaled raw_status ) {
            = ec + 128 ( nurl_wait_term_sig raw_status )
        } {}
    }
    = . c exit_code ec
    = . c waited 1
    ^ ec
}

@ __proc_kill_posix * ProcChildImpl c i sig → i {
    : i pid . c pid
    ? <= pid 0 { ^ -1 } {}
    : i sg ? > sig 0 sig ( posix_const `SIGTERM` )
    : i rc ( kill pid sg )
    ? < rc 0 {
        = . c last_io_err ( nurl_errno_get )
        ^ -1
    } {}
    ^ 0
}

// best-effort reap helper — SIGTERM, poll waitpid(WNOHANG) for up to
// 500ms, then SIGKILL + blocking wait if still alive.
@ __proc_reap_posix i pid i waited → v {
    ? || <= pid 0 != waited 0 {} {
        ( kill pid ( posix_const `SIGTERM` ) )
        : ( Vec i ) status_v ( vec_zeroed [i] 1 )
        : *u status_p # *u ( vec_data [i] status_v )
        : ~ i tries 0
        : ~ i reaped 0
        ~ < tries 50 {
            : i w ( waitpid pid status_p ( posix_const `WNOHANG` ) )
            ? == w pid { = reaped 1 = tries 50 } {
                ? < w 0 { = tries 50 } {}
            }
            ? == reaped 0 {
                // The SIGTERM's grace: 50 polls 10 ms apart, then SIGKILL.
                // (Without the sleep the polls ran back to back and every
                // child that did not exit at once was killed within
                // microseconds.)
                ( sleep_ms 10 )
                = tries + tries 1
            } {}
        }
        ? == reaped 0 {
            ( kill pid ( posix_const `SIGKILL` ) )
            ( waitpid pid status_p 0 )
        } {}
    }
}

@ process_spawn s cmd ( Vec s ) args → !ProcChild ProcessErr {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __process_spawn_posix cmd args )
    } {}
    : *s argv ( vec_data [s] args )
    : i argc ( vec_len [s] args )
    : s argv_buf # s argv
    ^ ( __proc_spawn_dispatch ( __pc_from_c ( nurl_proc_spawn cmd argv_buf argc ) ) )
}

@ process_spawn0 s cmd → !ProcChild ProcessErr {
    : ( Vec s ) args ( vec_new [s] )
    : !ProcChild ProcessErr res ( process_spawn cmd args )
    ^ res
}

@ process_spawn1 s cmd s a0 → !ProcChild ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 1 )
    ( vec_push [s] args a0 )
    : !ProcChild ProcessErr res ( process_spawn cmd args )
    ^ res
}

@ process_spawn2 s cmd s a0 s a1 → !ProcChild ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 2 )
    ( vec_push [s] args a0 )
    ( vec_push [s] args a1 )
    : !ProcChild ProcessErr res ( process_spawn cmd args )
    ^ res
}

@ proc_pid ProcChild p → i {
    ? != ( posix_const `O_NONBLOCK` ) -1 { ^ . ( __proc_st p ) pid } {}
    ^ ( nurl_proc_spawn_pid ( __proc_raw p ) )
}

@ proc_write ProcChild p * u buf i n → i {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __proc_write_posix ( __proc_st p ) # s buf n )
    } {}
    ^ ( nurl_proc_spawn_write ( __proc_raw p ) # s buf n )
}

@ proc_write_str ProcChild p s s_view → i {
    : i n ( nurl_str_len s_view )
    ^ ( proc_write p s_view n )
}

@ proc_write_line ProcChild p s line → i {
    : i n0 ( proc_write_str p line )
    ? < n0 0 { ^ -1 } {}
    : i n1 ( proc_write_str p `\n` )
    ? < n1 0 { ^ -1 } {}
    ^ + n0 n1
}

@ proc_close_stdin ProcChild p → v {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ( __proc_close_stdin_posix ( __proc_st p ) )
    } {
        ( nurl_proc_spawn_close_stdin ( __proc_raw p ) )
    }
}

@ proc_eof ProcChild p → b {
    ? != ( posix_const `O_NONBLOCK` ) -1 { ^ != 0 . ( __proc_st p ) eof } {}
    ^ != 0 ( nurl_proc_spawn_eof ( __proc_raw p ) )
}

@ proc_last_io_err ProcChild p → i {
    ? != ( posix_const `O_NONBLOCK` ) -1 { ^ . ( __proc_st p ) last_io_err } {}
    ^ ( nurl_proc_spawn_last_io_err ( __proc_raw p ) )
}

// Read one '\n'-delimited line from the child's stdout. Returns:
//   * Some(String)  — a fresh OWNED line (newline stripped).
//   * None on timeout (proc_eof = false) OR EOF (proc_eof = true).
// `timeout_ms <= 0` blocks until a full line arrives or EOF/error.
@ proc_read_line ProcChild p i timeout_ms → ?String {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        : *ProcChildImpl c ( __proc_st p )
        : s view ( __proc_read_line_posix c timeout_ms )
        ? <= ( vec_len [u] . c line ) 1 { ^ @ ?String { F # String 0 } } {}
        ^ @ ?String { T ( string_from view ) }
    } {}
    : i raw ( __proc_raw p )
    : s cview ( nurl_proc_spawn_read_line raw timeout_ms )
    ? == 0 ( nurl_proc_spawn_read_line_len raw ) { ^ @ ?String { F # String 0 } } {}
    ^ @ ?String { T ( string_from cview ) }
}

// Blocking raw-byte read from the child's stdout — the incremental
// dual of proc_write. Blocks until the child produces output (or EOF),
// then returns ONE read(2)-worth of bytes, at most `max`. Returns:
//   * Ok(Vec u)  — fresh OWNED bytes. EMPTY ⇒ EOF
//     (proc_eof = true from then on).
//   * Err(ProcessIo) on a hard pipe error (errno via proc_last_io_err).
// Bytes buffered by an earlier proc_read_line are served first.
// POSIX only; Win32/WASI return ProcessOther (use proc_read_line).
@ proc_read_chunk ProcChild p i max → !( Vec u ) ProcessErr {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __proc_read_chunk_posix ( __proc_st p ) max )
    } {}
    ^ @ !( Vec u ) ProcessErr { F # ProcessErr ProcessOther }
}

// Full-write a byte Vec to the child's stdin. Returns bytes written
// (== vec_len on success) or -1 on error, like proc_write.
@ proc_write_bytes ProcChild p ( Vec u ) data → i {
    : i n ( vec_len [u] data )
    ? <= n 0 { ^ 0 } {}
    : *u dp ( vec_data [u] data )
    : s buf # s # i dp
    ^ ( proc_write p buf n )
}

@ proc_wait ProcChild p → i {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __proc_wait_posix ( __proc_st p ) )
    } {}
    ^ ( nurl_proc_spawn_wait ( __proc_raw p ) )
}

@ proc_kill ProcChild p i sig → i {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __proc_kill_posix ( __proc_st p ) sig )
    } {}
    ^ ( nurl_proc_spawn_kill ( __proc_raw p ) sig )
}

// Let go of `p` now rather than at the end of its owner's scope; the
// last owner shuts the child down.
@ proc_free sink ProcChild p → v {}

// ── The process's own identity ──────────────────────────────────────
// Its user and group ids, real and effective, and its supplementary
// groups — 0 and none where the platform has no such notion (Windows,
// the unikernel), which is what those report for whoami / id.

& `c` @ nurl_self_id i kind → i

& `c` @ nurl_self_groups *i out i cap → i

@ proc_self_uid → i { ^ ( nurl_self_id 0 ) }

@ proc_self_euid → i { ^ ( nurl_self_id 1 ) }

@ proc_self_gid → i { ^ ( nurl_self_id 2 ) }

@ proc_self_egid → i { ^ ( nurl_self_id 3 ) }

@ proc_self_groups → ( Vec i ) {
    : ~ i cap 32
    ~ T {
        : ( Vec i ) out ( vec_zeroed [i] cap )
        : i n ( nurl_self_groups ( vec_data [i] out ) cap )
        ? <= n 0 { ^ ( vec_new [i] ) } {}
        ? <= n cap {
            : b _t ( vec_truncate [i] out n )
            ^ out
        } {}
        = cap n
    }
    ^ ( vec_new [i] )
}

// ── POSIX process control without pointers ──────────────────────────
//
// fork, dup2, close and _exit take and return plain integers and are
// called as they are. What follows wraps the primitives that pass a
// buffer — waitpid's status word, pipe's descriptor pair, execvp's argv
// array, read's destination — so a shell, a supervisor or a test harness
// controls processes without handling an address.

// The two ends of a pipe(2): bytes written to `wr` are read from `rd`.
: PosixPipe { i rd i wr }

// pipe(2); F when the call failed (descriptor table full, or no pipes on
// this machine).
@ posix_pipe → ?PosixPipe {
    : ( Vec i32 ) fds ( vec_zeroed [i32] 2 )
    ? < # i ( pipe # *u ( vec_data [i32] fds ) ) 0 { ^ @ ?PosixPipe { F } } {}
    ^ @ ?PosixPipe { T @ PosixPipe { # i ( vec_at [i32] fds 0 ) # i ( vec_at [i32] fds 1 ) } }
}

// waitpid(pid, 0): wait for the child to end. Its exit code, 128 + the
// signal number when a signal ended it, -1 when `pid` is not a child.
@ posix_wait_exit i pid → i {
    : ( Vec i32 ) status ( vec_zeroed [i32] 2 )
    ? < # i ( waitpid # i32 pid # *u ( vec_data [i32] status ) # i32 0 ) 0 { ^ -1 } {}
    ^ ( nurl_wait_exit_status & # i ( vec_at [i32] status 0 ) 65535 )
}

// execvp(3) of `argv[from]` (looked up in PATH) with arguments
// `argv[from..]`: this process becomes that program. Returns only when the
// exec failed, with the errno (ENOENT: not found, EACCES: not runnable);
// -1 when there is no program to run.
@ posix_execvp ( Vec String ) argv i from → i {
    : i n - ( vec_len [String] argv ) from
    ? | <= n 0 < from 0 { ^ -1 } {}
    // The NUL-terminated pointer array execvp reads: each entry the
    // address of a String this function's caller keeps alive until exec.
    : ( Vec i ) ptrs ( vec_zeroed [i] + n 1 )
    : ~ i k 0
    ~ < k n {
        ( vec_put [i] ptrs k # i ( string_data ( vec_at [String] argv + from k ) ) )
        = k + k 1
    }
    : i32 _rc ( execvp ( string_data ( vec_at [String] argv from ) ) # *u ( vec_data [i] ptrs ) )
    ^ ( nurl_errno_get )
}

// Append up to `max` bytes read(2) from `fd` to `buf`. The count read: 0 at
// end of input, -1 on an error (errno says which).
@ posix_read_append i fd ( Vec u ) buf i max → i {
    ? <= max 0 { ^ 0 } {}
    : i len ( vec_len [u] buf )
    ( vec_reserve [u] buf max )
    : i got ( read # i32 fd # *u + # i ( vec_data [u] buf ) len max )
    ? > got 0 { : b _l ( vec_set_len [u] buf + len got ) } {}
    ^ got
}

// Run `argv[from..]` as a child that shares this process's stdin, stdout
// and stderr, and wait for it: its exit status as posix_wait_exit gives it,
// 127 when the program could not be run, -1 where there are no processes.
// Pending stdout is flushed first, so the child's output follows ours.
@ process_run_inherit ( Vec String ) argv i from → i {
    ? <= - ( vec_len [String] argv ) from 0 { ^ 127 } {}
    ( nurl_flush_stdout )
    : i pid # i ( fork )
    ? < pid 0 { ^ -1 } {}
    ? == pid 0 {
        : i _e ( posix_execvp argv from )
        ( _exit # i32 127 )
    } {}
    ^ ( posix_wait_exit pid )
}

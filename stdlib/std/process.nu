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
//   ( output_free      Output o )                  → v    cascades buffers
//   ( output_success   Output o )                  → b    exit_code == 0
//
//   ( process_err_name ProcessErr e )              → s    diagnostic
//
// Memory model — single-owner, LLM-friendly:
//
//   * Each call returns a fresh OWNED Output. The caller MUST call
//     `output_free` exactly once on the Result-Ok path. (ProcessErr arms
//     produced by these wrappers never carry an Output handle, so no
//     free is necessary on the error path.)
//   * The Output wraps a heap NurlProcResult allocated by the runtime
//     that owns the stdout + stderr buffers. `output_free` cascades
//     to both of them.
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
//   * Win32 backend uses CreateProcess + reader threads. `cmd` is
//     looked up via the standard PATH search; pass an absolute path
//     when in doubt.
//   * wasm32-wasi: every call returns ProcessOther.
//
// MVP scope — explicitly left for a follow-up:
//   - per-call timeout / cancellation
//   - streaming stdout/stderr (currently full-buffer capture)
//   - environment variable overrides for the child
//   - cwd override for the child

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/posix.nu`

: | ProcessErr { ProcessNotFound ProcessExecFailed ProcessIo ProcessOther }

// Output is an opaque single-field handle around the runtime's
// NurlProcResult. Accessors below project into typed views.
: Output { s raw }

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
@ __process_dispatch i raw → !Output ProcessErr {
    ? == raw 0 { ^ @ !Output ProcessErr { F # ProcessErr ProcessOther } } {}
    : i ek ( nurl_proc_err_kind raw )
    ? != ek 0 {
        ( nurl_proc_free raw )
        ? == ek 1 { ^ @ !Output ProcessErr { F # ProcessErr ProcessNotFound } } {}
        ? == ek 2 { ^ @ !Output ProcessErr { F # ProcessErr ProcessExecFailed } } {}
        ? == ek 3 { ^ @ !Output ProcessErr { F # ProcessErr ProcessIo } } {}
        ^ @ !Output ProcessErr { F # ProcessErr ProcessOther }
    } {}
    : s rp # s raw
    : Output o @ Output { rp }
    ^ @ !Output ProcessErr { T o }
}

// ── PURIFY Phase 8 batch 2 — pure-NURL POSIX backend ────────────────
// Allocates a NurlProcResult-shaped 48-byte heap struct that the
// existing C accessors (`nurl_proc_exit_code` / `_stdout` / `_stderr`
// / `_stdout_len` / `_stderr_len` / `_err_kind` / `_free`) project
// into. Layout (matches stdlib/runtime.c §16 NurlProcResult exactly):
//   slot 0: exit_code   (i64)
//   slot 1: err_kind    (i64)
//   slot 2: stdout_buf  (heap, NUL-terminated, malloc'd via nurl_alloc)
//   slot 3: stdout_len  (i64)
//   slot 4: stderr_buf  (heap, NUL-terminated, malloc'd via nurl_alloc)
//   slot 5: stderr_len  (i64)
//
// On Win32 / WASI the FFI symbols below (fork / pipe / execvp / poll /
// waitpid / fcntl) aren't available; `process_run` gates the whole
// pure-NURL path on `posix_const "O_NONBLOCK" != -1` and falls
// through to the runtime's C `nurl_proc_run` there.

// Allocate a fresh 1-byte buffer holding a single NUL — the
// strdup("") equivalent that nurl_proc_free / the accessors expect
// for empty captures.
@ __proc_empty_buf → s {
    : s p ( nurl_alloc 1 )
    : *u up # *u p
    = . up 0 # u 0
    ^ p
}

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

// Build a NULL-terminated argv array on the heap: [cmd, args..., NULL].
// Caller frees with nurl_free.
@ __build_argv s cmd ( Vec s ) args → s {
    : i argc ( vec_len [s] args )
    : i full_n + argc 2
    : s full ( nurl_alloc * full_n 8 )
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
    ^ full
}

// Heap-grown byte buffer for capturing child stdout / stderr. The
// final pointer is stored verbatim into a NurlProcResult slot and
// freed by the C-side nurl_proc_free, so it must come from nurl_alloc
// (== malloc).
@ __pb_grow s data i cap i need → s {
    ? <= need cap { ^ data } {}
    : ~ i newcap cap
    ~ < newcap need { = newcap * newcap 2 }
    ^ ( nurl_realloc data newcap )
}

// Append n bytes from src into the (data, len, cap) buffer. Returns
// the (possibly grown) data pointer; caller updates len + cap from
// the new state. We use a 3-slot scratch struct stored at `state` to
// avoid multi-return: state[0] = data ptr (i), [1] = len, [2] = cap.
@ __pb_append s state s src i n → v {
    ? <= n 0 {} {
        : s data # s ( nurl_peek state 0 )
        : i len ( nurl_peek state 1 )
        : i cap ( nurl_peek state 2 )
        : i want + + len n 1
        : s new_data ( __pb_grow data cap want )
        : i new_cap ? > want cap want cap
        : *u dst_base # *u new_data
        : *u dst_at # *u + # i dst_base len
        : *u src_p # *u src
        ( nurl_memcpy dst_at src_p n )
        : i new_len + len n
        ( nurl_poke state 0 # i new_data )
        ( nurl_poke state 1 new_len )
        ( nurl_poke state 2 new_cap )
    }
}

// Finalize: ensure NUL-terminator past `len`, return the heap pointer
// (caller transfers ownership to NurlProcResult). State is consumed.
@ __pb_finalize s state → s {
    : s data # s ( nurl_peek state 0 )
    : i len ( nurl_peek state 1 )
    : i cap ( nurl_peek state 2 )
    : s ensured ( __pb_grow data cap + len 1 )
    : *u up # *u ensured
    = . up len # u 0
    ^ ensured
}

// Allocate the (data, len, cap) state block. Initial cap = 256 bytes.
@ __pb_state_new → s {
    : s st ( nurl_alloc 24 )
    : s data ( nurl_alloc 256 )
    ( nurl_poke st 0 # i data )
    ( nurl_poke st 1 0 )
    ( nurl_poke st 2 256 )
    ^ st
}

// Drain a non-blocking fd into the pb state. Returns -1 on EOF or hard
// error (caller closes the fd), 0 on EAGAIN (more data later). The
// `tmp_buf` is a caller-owned 4 KiB scratch buffer.
@ __pb_drain_fd i fd s state s tmp_buf → i {
    ~ T {
        : i rd ( read fd # *u tmp_buf 4096 )
        ? > rd 0 {
            ( __pb_append state tmp_buf rd )
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
    : s buf ( nurl_zalloc 4 )
    : *u up # *u buf
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
    : i val ( __le32_read up 0 )
    ( nurl_free buf )
    ^ val
}

// Write the child's errno to the exec-error sideband. Best-effort.
@ __write_exec_errno i fd i errno_val → v {
    : s buf ( nurl_alloc 4 )
    : *u up # *u buf
    ( __le32_write up 0 errno_val )
    ( write fd # *u buf 4 )
    ( nurl_free buf )
}

// Map a child-side exec errno to NurlProcResult err_kind.
@ __map_exec_errno i e → i {
    ? == e ( posix_const `ENOENT` ) { ^ 1 } {}  // NotFound
    ^ 2  // ExecFailed
}

// Decode waitpid status (raw int) into a (exit_code, err_kind) pair.
// Writes the pair into the result struct directly.
@ __decode_status s r i raw_status i io_err i child_errno → v {
    ? != child_errno 0 {
        ( nurl_poke r 0 -1 )
        ( nurl_poke r 1 ( __map_exec_errno child_errno ) )
    } { ? != io_err 0 {
            ( nurl_poke r 0 -1 )
            ( nurl_poke r 1 3 )  // Io
        } { ? == ( nurl_wait_is_exited raw_status ) 1 {
                ( nurl_poke r 0 ( nurl_wait_exit_status raw_status ) )
                ( nurl_poke r 1 0 )  // ok
            } { ? == ( nurl_wait_is_signaled raw_status ) 1 {
                    ( nurl_poke r 0 + 128 ( nurl_wait_term_sig raw_status ) )
                    ( nurl_poke r 1 0 )  // ok
                } {
                    ( nurl_poke r 0 -1 )
                    ( nurl_poke r 1 4 )  // Other
                } } } }
}

// Main entry — translated step-by-step from runtime.c §16
// `nurl_proc_run` POSIX backend.
@ __process_run_posix s cmd ( Vec s ) args s stdin_str → !Output ProcessErr {
    : s r ( nurl_zalloc 48 )

    : i cmd_len ( nurl_str_len cmd )
    ? <= cmd_len 0 {
        ( nurl_poke r 1 1 )  // NotFound
        ( nurl_poke r 2 # i ( __proc_empty_buf ) )
        ( nurl_poke r 4 # i ( __proc_empty_buf ) )
        ^ ( __process_dispatch # i r )
    } {}

    // Four 2-int pipe buffers. fd values land at offsets 0 + 4 of each.
    : s sin_p ( nurl_alloc 8 )
    : s sout_p ( nurl_alloc 8 )
    : s serr_p ( nurl_alloc 8 )
    : s err_p ( nurl_alloc 8 )

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
        ( nurl_free sin_p ) ( nurl_free sout_p )
        ( nurl_free serr_p ) ( nurl_free err_p )
        ( nurl_poke r 1 3 )  // Io
        ( nurl_poke r 2 # i ( __proc_empty_buf ) )
        ( nurl_poke r 4 # i ( __proc_empty_buf ) )
        ^ ( __process_dispatch # i r )
    } {}

    // CLOEXEC on err_p[1] so a successful exec triggers EOF on read.
    ( __set_cloexec ( __pipe_fd err_p 1 ) )

    : s full ( __build_argv cmd args )

    : i pid ( fork )
    ? < pid 0 {
        ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        ( close ( __pipe_fd serr_p 0 ) ) ( close ( __pipe_fd serr_p 1 ) )
        ( close ( __pipe_fd err_p 0 ) ) ( close ( __pipe_fd err_p 1 ) )
        ( nurl_free sin_p ) ( nurl_free sout_p )
        ( nurl_free serr_p ) ( nurl_free err_p )
        ( nurl_free full )
        ( nurl_poke r 1 3 )  // Io
        ( nurl_poke r 2 # i ( __proc_empty_buf ) )
        ( nurl_poke r 4 # i ( __proc_empty_buf ) )
        ^ ( __process_dispatch # i r )
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
        ( execvp cmd # *u full )
        : i e ( nurl_errno_get )
        ( __write_exec_errno ( __pipe_fd err_p 1 ) e )
        ( _exit 127 )
    } {}

    // Parent: free argv (the child has its own copy via fork).
    ( nurl_free full )

    // Close child-side pipe ends.
    ( close ( __pipe_fd sin_p 0 ) )
    ( close ( __pipe_fd sout_p 1 ) )
    ( close ( __pipe_fd serr_p 1 ) )
    ( close ( __pipe_fd err_p 1 ) )

    : i sin_wfd ( __pipe_fd sin_p 1 )
    : i sout_rfd ( __pipe_fd sout_p 0 )
    : i serr_rfd ( __pipe_fd serr_p 0 )
    : i err_rfd ( __pipe_fd err_p 0 )
    ( nurl_free sin_p ) ( nurl_free sout_p )
    ( nurl_free serr_p ) ( nurl_free err_p )

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
    : s out_state ( __pb_state_new )
    : s err_state ( __pb_state_new )
    : s tmp_buf ( nurl_alloc 4096 )
    : s pollfds ( nurl_alloc 16 )
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
                    : s ds ? == fd sout_rfd out_state err_state
                    : i drain_rc ( __pb_drain_fd fd ds tmp_buf )
                    : i hup_or_err & rev | ( posix_const `POLLHUP` ) ( posix_const `POLLERR` )
                    ? || == drain_rc -1 != hup_or_err 0 {
                        ? == fd sout_rfd { = out_open 0 } { = err_open 0 }
                    } {}
                } {}
                = k + k 1
            }
        }
    }

    ( nurl_free tmp_buf )
    ( nurl_free pollfds )

    ( close sout_rfd )
    ( close serr_rfd )

    : i child_errno ( __read_exec_errno err_rfd )
    ( close err_rfd )

    // waitpid with EINTR retry.
    : s status_buf ( nurl_alloc 4 )
    : *u status_p # *u status_buf
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
    ( nurl_free status_buf )

    ( __decode_status r raw_status io_err child_errno )

    // Finalize buffers and hand over to the result struct.
    : i out_len ( nurl_peek out_state 1 )
    : i err_len ( nurl_peek err_state 1 )
    : s out_buf ( __pb_finalize out_state )
    : s err_buf ( __pb_finalize err_state )
    ( nurl_free out_state )
    ( nurl_free err_state )

    ( nurl_poke r 2 # i out_buf )
    ( nurl_poke r 3 out_len )
    ( nurl_poke r 4 # i err_buf )
    ( nurl_poke r 5 err_len )

    ^ ( __process_dispatch # i r )
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
    : i raw ( nurl_proc_run cmd argv_buf argc stdin_str )
    ^ ( __process_dispatch raw )
}

// ── Convenience arities ────────────────────────────────────────────

@ process_run0 s cmd → !Output ProcessErr {
    : ( Vec s ) args ( vec_new [s] )
    : !Output ProcessErr res ( process_run cmd args `` )
    ( vec_free [s] args )
    ^ res
}

@ process_run1 s cmd s a0 → !Output ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 1 )
    ( vec_push [s] args a0 )
    : !Output ProcessErr res ( process_run cmd args `` )
    ( vec_free [s] args )
    ^ res
}

@ process_run2 s cmd s a0 s a1 → !Output ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 2 )
    ( vec_push [s] args a0 )
    ( vec_push [s] args a1 )
    : !Output ProcessErr res ( process_run cmd args `` )
    ( vec_free [s] args )
    ^ res
}

@ process_run3 s cmd s a0 s a1 s a2 → !Output ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 3 )
    ( vec_push [s] args a0 )
    ( vec_push [s] args a1 )
    ( vec_push [s] args a2 )
    : !Output ProcessErr res ( process_run cmd args `` )
    ( vec_free [s] args )
    ^ res
}

// Run a shell pipeline via /bin/sh -c (or cmd.exe /c on Windows).
// Convenient for one-liners with quoting / redirection / pipes that
// would otherwise need awkward argv handling.
@ process_run_shell s sh_cmd → !Output ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 2 )
    ( vec_push [s] args `-c` )
    ( vec_push [s] args sh_cmd )
    : !Output ProcessErr res ( process_run `/bin/sh` args `` )
    ( vec_free [s] args )
    ^ res
}

// ── Accessors (borrowed views into the runtime-owned buffers) ───────

@ output_exit_code Output o → i {
    : s rp . o raw
    : i raw # i rp
    ^ ( nurl_proc_exit_code raw )
}

@ output_stdout Output o → s {
    : s rp . o raw
    : i raw # i rp
    ^ ( nurl_proc_stdout raw )
}

@ output_stderr Output o → s {
    : s rp . o raw
    : i raw # i rp
    ^ ( nurl_proc_stderr raw )
}

@ output_stdout_len Output o → i {
    : s rp . o raw
    : i raw # i rp
    ^ ( nurl_proc_stdout_len raw )
}

@ output_stderr_len Output o → i {
    : s rp . o raw
    : i raw # i rp
    ^ ( nurl_proc_stderr_len raw )
}

@ output_success Output o → b {
    ^ == 0 ( output_exit_code o )
}

@ output_free Output o → v {
    : s rp . o raw
    : i raw # i rp
    ( nurl_proc_free raw )
}

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
//   ( proc_write        ProcChild p s buf i n ) → i      bytes written, -1 err
//   ( proc_write_str    ProcChild p s s_view )  → i
//   ( proc_write_line   ProcChild p s line )    → i      appends '\n'
//   ( proc_close_stdin  ProcChild p )           → v
//
//   ( proc_read_line    ProcChild p i timeout_ms )
//                                              → ? String   None on timeout/EOF
//   ( proc_eof          ProcChild p )           → b
//   ( proc_last_io_err  ProcChild p )           → i      raw errno
//
//   ( proc_wait         ProcChild p )           → i      blocks
//   ( proc_kill         ProcChild p i sig )     → i      0 ok / -1 err
//   ( proc_free         ProcChild p )           → v      reaps child
//
// Memory model:
//   * `proc_read_line` returns a freshly-OWNED `String` on Some — the
//     caller MUST `string_free` it. None means timeout (peer still alive,
//     `proc_eof` = false) OR EOF (peer closed, `proc_eof` = true).
//   * `proc_free` cascades: closes stdin/stdout, SIGTERMs an unwaited
//     child (then SIGKILL after ~500ms), reaps via waitpid, frees the
//     handle.
//   * Args Vec is BORROWED — element pointers must outlive the spawn call.

: ProcChild { s raw }

@ __proc_spawn_dispatch i raw → !ProcChild ProcessErr {
    ? == raw 0 { ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessOther } } {}
    : i ek ( nurl_proc_spawn_err_kind raw )
    ? != ek 0 {
        ( nurl_proc_spawn_free raw )
        ? == ek 1 { ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessNotFound } } {}
        ? == ek 2 { ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessExecFailed } } {}
        ? == ek 3 { ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessIo } } {}
        ^ @ !ProcChild ProcessErr { F # ProcessErr ProcessOther }
    } {}
    : s rp # s raw
    : ProcChild p @ ProcChild { rp }
    ^ @ !ProcChild ProcessErr { T p }
}

// ── PURIFY Phase 8 batch 3 — pure-NURL POSIX spawn backend ─────────
//
// NurlProcChild heap struct layout (16 slots × 8 bytes = 128 bytes,
// nurl_zalloc'd; same struct C-side accessors below project into):
//
//   0  err_kind         (0 / NURL_PROC_ERR_*)
//   1  last_io_err      (errno snapshot)
//   2  exit_code        (-1 until wait succeeds)
//   3  eof              (0 / 1)
//   4  waited           (0 / 1)
//   5  pid_or_0         (logical pid; same as pid on POSIX)
//   6  pid              (POSIX pid_t widened to i64)
//   7  fd_in            (-1 once closed)
//   8  fd_out           (-1 once closed)
//   9  scratch          (heap byte buffer, NULL until first read)
//   10 scratch_len      (bytes currently held)
//   11 scratch_cap      (allocation size)
//   12 line_buf         (heap byte buffer for the most-recent line)
//   13 line_len         (length, no trailing NUL)
//   14 line_cap         (allocation size incl. terminator)
//   15 reserved

@ __pc_alloc → s {
    : s c ( nurl_zalloc 128 )
    ( nurl_poke c 2 -1 )  // exit_code = -1
    ( nurl_poke c 7 -1 )  // fd_in = -1
    ( nurl_poke c 8 -1 )  // fd_out = -1
    ^ c
}

// scratch_reserve / line_reserve / drain_line — translated from C
// §16b's static helpers verbatim.

@ __pc_scratch_reserve s c i want → v {
    : i cap ( nurl_peek c 11 )
    ? >= cap want {} {
        : ~ i newcap ? > cap 0 cap 1024
        ~ < newcap want { = newcap * newcap 2 }
        : s old # s ( nurl_peek c 9 )
        : s p ( nurl_realloc old newcap )
        ( nurl_poke c 9 # i p )
        ( nurl_poke c 11 newcap )
    }
}

@ __pc_line_reserve s c i want → v {
    : i cap ( nurl_peek c 14 )
    ? >= cap + want 1 {} {
        : ~ i newcap ? > cap 0 cap 256
        ~ < newcap + want 1 { = newcap * newcap 2 }
        : s old # s ( nurl_peek c 12 )
        : s p ( nurl_realloc old newcap )
        ( nurl_poke c 12 # i p )
        ( nurl_poke c 14 newcap )
    }
}

// Try to extract the first '\n'-terminated line from scratch into
// line_buf. Returns 1 on success. The trailing '\n' is consumed but
// not copied; an optional '\r' before it is also stripped.
@ __pc_drain_line s c → i {
    : s scratch # s ( nurl_peek c 9 )
    : i scratch_len ( nurl_peek c 10 )
    ? == # i scratch 0 { ^ 0 } {}
    : *u sp # *u scratch
    : ~ i i 0
    ~ < i scratch_len {
        : i b & 255 # i . sp i
        ? == b 10 {  // '\n'
            : ~ i take i
            ? > take 0 {
                : i prev & 255 # i . sp - take 1
                ? == prev 13 { = take - take 1 } {}  // '\r'
            } {}
            ( __pc_line_reserve c take )
            : s line # s ( nurl_peek c 12 )
            ? > take 0 {
                : *u dst # *u line
                ( nurl_memcpy dst sp take )
            } {}
            : *u lp # *u line
            = . lp take # u 0
            ( nurl_poke c 13 take )
            : i consume + i 1
            : i rem - scratch_len consume
            ? > rem 0 {
                // dst (scratch base) and src (scratch + consume) alias
                // — shift the tail back over the consumed prefix with
                // memmove, not memcpy. memcpy is UB on overlap and
                // ASan flags it correctly under -fsanitize=address.
                : *u dst2 # *u scratch
                : *u src2 # *u + # i sp consume
                ( nurl_memmove dst2 src2 rem )
            } {}
            ( nurl_poke c 10 rem )
            ^ 1
        } {}
        = i + i 1
    }
    ^ 0
}

@ __process_spawn_posix s cmd ( Vec s ) args → !ProcChild ProcessErr {
    : s c ( __pc_alloc )

    : i cmd_len ( nurl_str_len cmd )
    ? <= cmd_len 0 {
        ( nurl_poke c 0 1 )  // NotFound
        ^ ( __proc_spawn_dispatch # i c )
    } {}

    : s sin_p ( nurl_alloc 8 )
    : s sout_p ( nurl_alloc 8 )
    : s err_p ( nurl_alloc 8 )

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
        ( nurl_free sin_p ) ( nurl_free sout_p ) ( nurl_free err_p )
        ( nurl_poke c 0 3 )  // Io
        ( nurl_poke c 1 ( nurl_errno_get ) )
        ^ ( __proc_spawn_dispatch # i c )
    } {}

    ( __set_cloexec ( __pipe_fd err_p 1 ) )

    : s full ( __build_argv cmd args )

    : i pid ( fork )
    ? < pid 0 {
        ( nurl_free full )
        ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        ( close ( __pipe_fd err_p 0 ) ) ( close ( __pipe_fd err_p 1 ) )
        ( nurl_free sin_p ) ( nurl_free sout_p ) ( nurl_free err_p )
        ( nurl_poke c 0 3 )  // Io
        ( nurl_poke c 1 ( nurl_errno_get ) )
        ^ ( __proc_spawn_dispatch # i c )
    } {}

    ? == pid 0 {
        ( dup2 ( __pipe_fd sin_p 0 ) 0 )
        ( dup2 ( __pipe_fd sout_p 1 ) 1 )
        // stderr inherits — no dup
        ( close ( __pipe_fd sin_p 0 ) ) ( close ( __pipe_fd sin_p 1 ) )
        ( close ( __pipe_fd sout_p 0 ) ) ( close ( __pipe_fd sout_p 1 ) )
        ( close ( __pipe_fd err_p 0 ) )
        ( execvp cmd # *u full )
        : i e ( nurl_errno_get )
        ( __write_exec_errno ( __pipe_fd err_p 1 ) e )
        ( _exit 127 )
    } {}

    ( nurl_free full )
    ( close ( __pipe_fd sin_p 0 ) )
    ( close ( __pipe_fd sout_p 1 ) )
    ( close ( __pipe_fd err_p 1 ) )

    : i sin_wfd ( __pipe_fd sin_p 1 )
    : i sout_rfd ( __pipe_fd sout_p 0 )
    : i err_rfd ( __pipe_fd err_p 0 )
    ( nurl_free sin_p ) ( nurl_free sout_p ) ( nurl_free err_p )

    : i child_errno ( __read_exec_errno err_rfd )
    ( close err_rfd )
    ? != child_errno 0 {
        ( close sin_wfd ) ( close sout_rfd )
        : s status_buf ( nurl_zalloc 4 )
        : *u status_p # *u status_buf
        ( waitpid pid status_p 0 )
        ( nurl_free status_buf )
        ( nurl_poke c 0 ( __map_exec_errno child_errno ) )
        ( nurl_poke c 1 child_errno )
        ^ ( __proc_spawn_dispatch # i c )
    } {}

    // Non-blocking on stdout so timeout-driven read_line doesn't wedge.
    ( __set_nonblock sout_rfd )

    ( nurl_poke c 5 pid )  // pid_or_0
    ( nurl_poke c 6 pid )  // pid
    ( nurl_poke c 7 sin_wfd )  // fd_in
    ( nurl_poke c 8 sout_rfd )  // fd_out
    ^ ( __proc_spawn_dispatch # i c )
}

@ __proc_write_posix i raw s buf i n → i {
    : s c # s raw
    : i fd_in ( nurl_peek c 7 )
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
                    ( nurl_poke c 1 e )
                    ( signal ( posix_const `SIGPIPE` ) old_pipe )
                    ^ -1
                }
            } { = total n }  // w == 0: break
        }
    }
    ( signal ( posix_const `SIGPIPE` ) old_pipe )
    ^ total
}

@ __proc_close_stdin_posix i raw → v {
    : s c # s raw
    : i fd_in ( nurl_peek c 7 )
    ? >= fd_in 0 {
        ( close fd_in )
        ( nurl_poke c 7 -1 )
    } {}
}

// One pollfd entry's worth of bytes for read_line's poll(2) call.
@ __proc_read_line_posix i raw i timeout_ms → s {
    : s c # s raw
    // Reset previous line.
    ( nurl_poke c 13 0 )
    : s prev_line # s ( nurl_peek c 12 )
    ? != # i prev_line 0 {
        : *u lp # *u prev_line
        = . lp 0 # u 0
    } {}

    ? == 1 ( __pc_drain_line c ) {
        : s line # s ( nurl_peek c 12 )
        ^ ? != # i line 0 line ``
    } {}

    : i fd_out ( nurl_peek c 8 )
    ? < fd_out 0 {
        ( nurl_poke c 3 1 )  // eof
        ^ ``
    } {}

    : s pollfds ( nurl_alloc 8 )
    : s chunk ( nurl_alloc 4096 )
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
            ( nurl_free pollfds ) ( nurl_free chunk )
            ^ ``  // timeout
        } {}
        ? < pr 0 {
            ( nurl_poke c 0 3 )  // Io
            ( nurl_poke c 1 ( nurl_errno_get ) )
            ( nurl_free pollfds ) ( nurl_free chunk )
            ^ ``
        } {}
        : i rev ( posix_pollfd_revents # *u pollfds 0 )
        : i has_in & rev pollin
        ? != has_in 0 {
            // Drain everything currently buffered.
            : ~ i drain_done 0
            ~ == drain_done 0 {
                : i rd ( read fd_out # *u chunk 4096 )
                ? > rd 0 {
                    : i scratch_len ( nurl_peek c 10 )
                    ( __pc_scratch_reserve c + scratch_len rd )
                    : s scratch_new # s ( nurl_peek c 9 )
                    : *u dst # *u + # i # *u scratch_new scratch_len
                    : *u src # *u chunk
                    ( nurl_memcpy dst src rd )
                    ( nurl_poke c 10 + scratch_len rd )
                } {
                    ? == rd 0 {
                        ( close fd_out )
                        ( nurl_poke c 8 -1 )
                        ( nurl_poke c 3 1 )  // eof
                        = drain_done 1
                    } {
                        : i re ( nurl_errno_get )
                        ? == re ( posix_const `EINTR` ) {} {
                            ? == re ( posix_const `EAGAIN` ) { = drain_done 1 } {
                                ? == re ( posix_const `EWOULDBLOCK` ) { = drain_done 1 } {
                                    ( nurl_poke c 0 3 )
                                    ( nurl_poke c 1 re )
                                    ( nurl_free pollfds ) ( nurl_free chunk )
                                    ^ ``
                                }
                            }
                        }
                    }
                }
            }
            : i hit_eof ( nurl_peek c 3 )
            ? == 1 ( __pc_drain_line c ) {
                ( nurl_free pollfds ) ( nurl_free chunk )
                : s line # s ( nurl_peek c 12 )
                ^ ? != # i line 0 line ``
            } {}
            // EOF without trailing '\n': flush tail.
            ? != hit_eof 0 {
                : i sc_len ( nurl_peek c 10 )
                ? > sc_len 0 {
                    ( __pc_line_reserve c sc_len )
                    : s line # s ( nurl_peek c 12 )
                    : s scratch # s ( nurl_peek c 9 )
                    : *u dst # *u line
                    : *u src # *u scratch
                    ( nurl_memcpy dst src sc_len )
                    : *u lp # *u line
                    = . lp sc_len # u 0
                    ( nurl_poke c 13 sc_len )
                    ( nurl_poke c 10 0 )
                    ( nurl_free pollfds ) ( nurl_free chunk )
                    ^ line
                } {}
                ( nurl_free pollfds ) ( nurl_free chunk )
                ^ ``
            } {}
        } {}
        : i hup_or_err & rev | pollhup pollerr
        ? != hup_or_err 0 {
            ( close fd_out )
            ( nurl_poke c 8 -1 )
            ( nurl_poke c 3 1 )  // eof
            ? == 1 ( __pc_drain_line c ) {
                ( nurl_free pollfds ) ( nurl_free chunk )
                : s line # s ( nurl_peek c 12 )
                ^ ? != # i line 0 line ``
            } {}
            : i sc_len ( nurl_peek c 10 )
            ? > sc_len 0 {
                ( __pc_line_reserve c sc_len )
                : s line # s ( nurl_peek c 12 )
                : s scratch # s ( nurl_peek c 9 )
                : *u dst # *u line
                : *u src # *u scratch
                ( nurl_memcpy dst src sc_len )
                : *u lp # *u line
                = . lp sc_len # u 0
                ( nurl_poke c 13 sc_len )
                ( nurl_poke c 10 0 )
                ( nurl_free pollfds ) ( nurl_free chunk )
                ^ line
            } {}
            ( nurl_free pollfds ) ( nurl_free chunk )
            ^ ``
        } {}
        // Loop — still no '\n' yet.
    }
    ( nurl_free pollfds ) ( nurl_free chunk )
    ^ ``
}

@ __proc_wait_posix i raw → i {
    : s c # s raw
    : i waited ( nurl_peek c 4 )
    ? != waited 0 { ^ ( nurl_peek c 2 ) } {}
    : i pid ( nurl_peek c 6 )
    ? <= pid 0 { ^ -1 } {}
    : s status_buf ( nurl_zalloc 4 )
    : *u status_p # *u status_buf
    : ~ i w 0
    : ~ i wait_done 0
    ~ == wait_done 0 {
        = w ( waitpid pid status_p 0 )
        ? >= w 0 { = wait_done 1 } {
            : i e ( nurl_errno_get )
            ? != e ( posix_const `EINTR` ) {
                = wait_done 1
                ( nurl_poke c 1 e )
                ( nurl_free status_buf )
                ^ -1
            } {}
        }
    }
    : i raw_status ( __le32_read status_p 0 )
    ( nurl_free status_buf )
    : ~ i ec -1
    ? == 1 ( nurl_wait_is_exited raw_status ) {
        = ec ( nurl_wait_exit_status raw_status )
    } {
        ? == 1 ( nurl_wait_is_signaled raw_status ) {
            = ec + 128 ( nurl_wait_term_sig raw_status )
        } {}
    }
    ( nurl_poke c 2 ec )
    ( nurl_poke c 4 1 )  // waited
    ^ ec
}

@ __proc_kill_posix i raw i sig → i {
    : s c # s raw
    : i pid ( nurl_peek c 6 )
    ? <= pid 0 { ^ -1 } {}
    : i s ? > sig 0 sig ( posix_const `SIGTERM` )
    : i rc ( kill pid s )
    ? < rc 0 {
        ( nurl_poke c 1 ( nurl_errno_get ) )
        ^ -1
    } {}
    ^ 0
}

// best-effort reap helper — SIGTERM, poll waitpid(WNOHANG) for up to
// 500ms, then SIGKILL + blocking wait if still alive.
@ __proc_reap_posix i raw → v {
    : s c # s raw
    : i pid ( nurl_peek c 6 )
    : i waited ( nurl_peek c 4 )
    ? || <= pid 0 != waited 0 {} {
        ( kill pid ( posix_const `SIGTERM` ) )
        : s status_buf ( nurl_zalloc 4 )
        : *u status_p # *u status_buf
        : ~ i tries 0
        : ~ i reaped 0
        ~ < tries 50 {
            : i w ( waitpid pid status_p ( posix_const `WNOHANG` ) )
            ? == w pid { = reaped 1 = tries 50 } {
                ? < w 0 { = tries 50 } {}
            }
            ? == reaped 0 {
                // 10ms sleep — simple busy-wait via repeated waitpid is
                // acceptable for the rare ungraceful-shutdown path.
                = tries + tries 1
            } {}
        }
        ? == reaped 0 {
            ( kill pid ( posix_const `SIGKILL` ) )
            ( waitpid pid status_p 0 )
        } {}
        ( nurl_free status_buf )
        ( nurl_poke c 4 1 )  // waited
    }
}

@ __proc_free_posix i raw → v {
    : s c # s raw
    ? == raw 0 {} {
        : i fd_in ( nurl_peek c 7 )
        ? >= fd_in 0 { ( close fd_in ) } {}
        : i fd_out ( nurl_peek c 8 )
        ? >= fd_out 0 { ( close fd_out ) } {}
        ( __proc_reap_posix raw )
        : s scratch # s ( nurl_peek c 9 )
        ? != # i scratch 0 { ( nurl_free scratch ) } {}
        : s line # s ( nurl_peek c 12 )
        ? != # i line 0 { ( nurl_free line ) } {}
        ( nurl_free c )
    }
}

@ process_spawn s cmd ( Vec s ) args → !ProcChild ProcessErr {
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __process_spawn_posix cmd args )
    } {}
    : *s argv ( vec_data [s] args )
    : i argc ( vec_len [s] args )
    : s argv_buf # s argv
    : i raw ( nurl_proc_spawn cmd argv_buf argc )
    ^ ( __proc_spawn_dispatch raw )
}

@ process_spawn0 s cmd → !ProcChild ProcessErr {
    : ( Vec s ) args ( vec_new [s] )
    : !ProcChild ProcessErr res ( process_spawn cmd args )
    ( vec_free [s] args )
    ^ res
}

@ process_spawn1 s cmd s a0 → !ProcChild ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 1 )
    ( vec_push [s] args a0 )
    : !ProcChild ProcessErr res ( process_spawn cmd args )
    ( vec_free [s] args )
    ^ res
}

@ process_spawn2 s cmd s a0 s a1 → !ProcChild ProcessErr {
    : ( Vec s ) args ( vec_with_cap [s] 2 )
    ( vec_push [s] args a0 )
    ( vec_push [s] args a1 )
    : !ProcChild ProcessErr res ( process_spawn cmd args )
    ( vec_free [s] args )
    ^ res
}

@ proc_pid ProcChild p → i {
    : s rp . p raw
    : i raw # i rp
    ^ ( nurl_proc_spawn_pid raw )
}

@ proc_write ProcChild p s buf i n → i {
    : s rp . p raw
    : i raw # i rp
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __proc_write_posix raw buf n )
    } {}
    ^ ( nurl_proc_spawn_write raw buf n )
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
    : s rp . p raw
    : i raw # i rp
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ( __proc_close_stdin_posix raw )
    } {
        ( nurl_proc_spawn_close_stdin raw )
    }
}

@ proc_eof ProcChild p → b {
    : s rp . p raw
    : i raw # i rp
    ^ != 0 ( nurl_proc_spawn_eof raw )
}

@ proc_last_io_err ProcChild p → i {
    : s rp . p raw
    : i raw # i rp
    ^ ( nurl_proc_spawn_last_io_err raw )
}

// Read one '\n'-delimited line from the child's stdout. Returns:
//   * Some(String)  — a fresh OWNED line (newline stripped). Free with string_free.
//   * None on timeout (proc_eof = false) OR EOF (proc_eof = true).
// `timeout_ms <= 0` blocks until a full line arrives or EOF/error.
@ proc_read_line ProcChild p i timeout_ms → ?String {
    : s rp . p raw
    : i raw # i rp
    : s view ? != ( posix_const `O_NONBLOCK` ) -1
    ( __proc_read_line_posix raw timeout_ms )
    ( nurl_proc_spawn_read_line raw timeout_ms )
    : i n ( nurl_proc_spawn_read_line_len raw )
    ? == n 0 { ^ @ ?String { F # String 0 } } {}
    ^ @ ?String { T ( string_from view ) }
}

@ proc_wait ProcChild p → i {
    : s rp . p raw
    : i raw # i rp
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __proc_wait_posix raw )
    } {}
    ^ ( nurl_proc_spawn_wait raw )
}

@ proc_kill ProcChild p i sig → i {
    : s rp . p raw
    : i raw # i rp
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ^ ( __proc_kill_posix raw sig )
    } {}
    ^ ( nurl_proc_spawn_kill raw sig )
}

@ proc_free ProcChild p → v {
    : s rp . p raw
    : i raw # i rp
    ? != ( posix_const `O_NONBLOCK` ) -1 {
        ( __proc_free_posix raw )
    } {
        ( nurl_proc_spawn_free raw )
    }
}

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

// Core entry point. `args` carries argv[1..]; argv[0] is `cmd` itself.
// `stdin_str` may be `` to send empty stdin.
@ process_run s cmd ( Vec s ) args s stdin_str → !Output ProcessErr {
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

@ process_spawn s cmd ( Vec s ) args → !ProcChild ProcessErr {
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
    ( nurl_proc_spawn_close_stdin raw )
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
    : s view ( nurl_proc_spawn_read_line raw timeout_ms )
    : i n ( nurl_proc_spawn_read_line_len raw )
    ? == n 0 { ^ @ ?String { F # String 0 } } {}
    ^ @ ?String { T ( string_from view ) }
}

@ proc_wait ProcChild p → i {
    : s rp . p raw
    : i raw # i rp
    ^ ( nurl_proc_spawn_wait raw )
}

@ proc_kill ProcChild p i sig → i {
    : s rp . p raw
    : i raw # i rp
    ^ ( nurl_proc_spawn_kill raw sig )
}

@ proc_free ProcChild p → v {
    : s rp . p raw
    : i raw # i rp
    ( nurl_proc_spawn_free raw )
}

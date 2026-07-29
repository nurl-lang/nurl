// stdlib/core/builtins.nu — the compiler's pre-registered runtime
// surface, as a documented module.
//
// Every function below is callable from ANY NURL program with no
// import at all: the compiler pre-registers these C-runtime symbols
// (they live in stdlib/runtime_core.c / runtime_ffi.c) and emits
// their `declare` lines into every module it compiles. This file
// exists so that surface is *discoverable* — nurldoc renders it,
// nurl_api indexes it, nurl_grep and nurl_read_stdlib see it — and a
// newcomer doesn't have to know which surface a symbol lives on.
//
// Importing this file is allowed and harmless (the compiler skips a
// duplicate `declare` for a symbol its preamble already carries), but
// it is never necessary.
//
// HAND-SYNCED with the preamble list in compiler/nurlc.nu;
// tools/check_builtins_doc.sh gates the two against each other in CI.
//
// Most of these have a friendlier, Result-typed stdlib wrapper — each
// section names it. Prefer the wrapper unless you need the raw call.

// ── Printing ────────────────────────────────────────────────────────
// Formatted templates live in stdlib/std/fmt.nu (println_fmt1…4);
// leveled logging in stdlib/std/log.nu.

// Print a string to stdout with NO trailing newline. Flushes.
& `c` @ nurl_print s text → v

// Print a string to stdout followed by a newline.
& `c` @ nurl_println s text → v

// Print a string to stderr with NO trailing newline. Flushes.
& `c` @ nurl_eprint s text → v

// Print a string to stderr followed by a newline.
& `c` @ nurl_eprintln s text → v

// Print an integer to stdout followed by a newline.
& `c` @ nurl_print_int i n → v

// Print a string to stdout followed by a newline (libc puts).
& `c` @ nurl_print_str s text → v

// Print `true` or `false` to stdout followed by a newline.
& `c` @ nurl_print_bool b x → v

// Flush buffered stdout / stderr explicitly.
& `c` @ nurl_flush_stdout → v

& `c` @ nurl_flush_stderr → v

// ── Reading stdin ───────────────────────────────────────────────────
// Buffered line/byte readers with error handling live in
// stdlib/std/bufio.nu.

// Read one integer from stdin (skips leading whitespace); 0 at EOF —
// check nurl_stdin_eof to tell the two apart.
& `c` @ nurl_read_int → i

// Read one line from stdin WITHOUT the trailing newline. Returns an
// owned string; "" at EOF (check nurl_stdin_eof).
& `c` @ nurl_read_line → s

// 1 once a previous read hit end-of-file on stdin, else 0.
& `c` @ nurl_stdin_eof → i

// ── Number ↔ string conversion ─────────────────────────────────────
// String-typed helpers (string_from, string_push_int, parse_int with
// a Result) live in stdlib/core/string.nu and stdlib/std/float.nu.

// Convert an integer to its decimal string form. Owned result.
& `c` @ nurl_str_int i n → s

// Convert a float (double) to its string form — shortest text that
// round-trips back to the same double. Owned result.
& `c` @ nurl_str_float f x → s

// Parse a float from the first `len` bytes at `p` (fast path, no
// locale). Prefer stdlib/std/float.nu's checked parsers for input
// validation.
& `c` @ nurl_fast_atof s p i len → f

// libc: parse an integer / float from a NUL-terminated string.
// No error reporting — 0 on garbage. Prefer string.nu / float.nu.
& `c` @ atoll s text → i

& `c` @ atof s text → f

// ── Byte scanning (SIMD hot paths) ─────────────────────────────────
// stdlib/std/bytes.nu and core/string.nu build on these.

// Offset of the first byte in p[0..len) equal to b0, b1, or b2, else
// `len`. SSE2-vectorised; duplicate a byte to scan for fewer targets.
& `c` @ nurl_scan_byte3 s p i len i b0 i b1 i b2 → i

// First-occurrence offset of needle[0..nlen) in hay[0..hlen), or -1.
// Empty needle returns 0.
& `c` @ nurl_byte_substr s hay i hlen s needle i nlen → i

// Count occurrences of byte `target` in p[0..len). memchr loop.
& `c` @ nurl_count_byte s p i len i target → i

// libc string primitives (NUL-terminated).
& `c` @ strlen s text → i

& `c` @ strcmp s a s b → i32

& `c` @ strncmp s a s b i n → i32

& `c` @ memcmp s a s b i n → i32

& `c` @ strstr s hay s needle → s

& `c` @ memmem s hay i hlen s needle i nlen → s

& `c` @ strdup s text → s

& `c` @ memcpy s dst s src i n → s

// ── Files & directories ────────────────────────────────────────────
// The real file API — Result-typed read/write/append, path checks,
// mkdir, glob — is stdlib/std/fs.nu. These are the raw calls.

// Read an entire file into an owned NUL-terminated string.
// EXITS THE PROCESS on open failure — use std/fs.nu's read_file for a
// Result instead.
& `c` @ nurl_read_file s path → s

// Directory listing, one entry per call: open returns a handle (0 on
// failure), next returns the entry name or "" when done, close frees.
// Prefer std/fs.nu's dir_list (Vec of names, Result-typed).
& `c` @ nurl_dir_list_open s path → i

& `c` @ nurl_dir_list_next i handle → s

& `c` @ nurl_dir_list_close i handle → v

// libc stdio pass-throughs (FILE* carried as `s`).
& `c` @ fopen s path s mode → s

& `c` @ fclose s handle → i32

& `c` @ fputs s text s handle → i32

& `c` @ fwrite s buf i size i count s handle → i

& `c` @ fputc i32 ch s handle → i32

& `c` @ fread s buf i size i count s handle → i

& `c` @ feof s handle → i32

& `c` @ fseek s handle i offset i32 whence → i32

& `c` @ ftell s handle → i

& `c` @ access s path i32 mode → i32

// ── Process, arguments, environment ────────────────────────────────
// stdlib/std/args.nu parses flags on top of these.

// Terminate the process with an exit code.
& `c` @ nurl_exit i code → v

// Command-line argument count / accessor (argv[0] = program path).
// Out-of-range index returns "". Results are owned copies.
& `c` @ nurl_argc → i

& `c` @ nurl_argv i idx → s

& `c` @ nurl_argv_count → i

& `c` @ nurl_argv_get i idx → s

// Toolchain version string, e.g. `0.28.0`.
& `c` @ nurl_version → s

// libc: environment variable value, or null. stdlib/ext/env.nu wraps
// this with defaults (env_var_or).
& `c` @ getenv s name → s

// libc: canonical absolute path (symlinks/.. resolved); null on
// failure. Pass null (`# *u 0`) as `resolved` to get a malloc'd result.
& `c` @ realpath s path s resolved → s

// ── Output capture ──────────────────────────────────────────────────

// Redirect nurl_print/nurl_println into an in-memory buffer (stackable);
// stop returns the captured text (owned) and pops, reset clears all.
& `c` @ nurl_print_buf_start → v

& `c` @ nurl_print_buf_stop → s

& `c` @ nurl_print_buf_reset → v

// ── Memory allocation ───────────────────────────────────────────────
// Typed containers (Vec, String, Box, arena) in core/vec.nu,
// core/string.nu, core/box.nu, core/mem.nu are the normal API; these
// are the raw allocators beneath them.

// Allocate `bytes` (small sizes hit a freelist cache) / zero-filled /
// resize / free. nurl_malloc is the uncached variant.
& `c` @ nurl_alloc i bytes → s

& `c` @ nurl_zalloc i bytes → s

& `c` @ nurl_realloc s ptr i bytes → s

& `c` @ nurl_free s ptr → v

& `c` @ nurl_malloc i bytes → s

// Raw byte moves/fill over possibly-overlapping regions.
& `c` @ nurl_memcpy s dst s src i n → v

& `c` @ nurl_memmove s dst s src i n → v

& `c` @ nurl_memset s dst i byte i n → v

// libc allocator (prefer nurl_alloc/nurl_free, which the leak tooling
// tracks).
& `c` @ malloc i bytes → s

& `c` @ free s ptr → v

// ── Floats ──────────────────────────────────────────────────────────
// Full float toolkit (bits, formatting, checked parse) in
// stdlib/std/float.nu and std/floatbits.nu.

// 1 when x is NaN / infinite, else 0.
& `c` @ nurl_is_nan f x → i

& `c` @ nurl_is_inf f x → i

// ── HTTP (raw) ─────────────────────────────────────────────────────
// USE stdlib/ext/http.nu — http_get/http_post and friends wrap these
// handles with headers, TLS, redirects, and streaming.

// One full request: returns a response handle (0 on failure). The _to
// variant takes connect/total timeouts (ms).
& `c` @ nurl_http_perform_full s method s url s headers s body → i

& `c` @ nurl_http_perform_full_to s method s url s headers s body i connect_ms i total_ms → i

& `c` @ nurl_http_response_free i handle → v

// Streaming body: open a handle, pump headers, then read chunks until
// "" (check EOF via the stream API in ext/http.nu).
& `c` @ nurl_http_stream_open_to s method s url s headers s body i connect_ms i total_ms → i

& `c` @ nurl_http_stream_next i handle → s

& `c` @ nurl_http_stream_close i handle → v

& `c` @ nurl_http_stream_pump_headers i handle → i

// ── Subprocesses (raw) ─────────────────────────────────────────────
// USE stdlib/std/process.nu — proc_run/proc_spawn wrap these with
// Result types and owned output.

// Run to completion: argv is NUL-joined, returns a handle; exit code,
// captured stdout/stderr (+ byte lengths) via accessors; free releases.
& `c` @ nurl_proc_run s argv s stdin_data i stdin_len s cwd → i

& `c` @ nurl_proc_exit_code i handle → i

& `c` @ nurl_proc_err_kind i handle → i

& `c` @ nurl_proc_stdout i handle → s

& `c` @ nurl_proc_stderr i handle → s

& `c` @ nurl_proc_stdout_len i handle → i

& `c` @ nurl_proc_stderr_len i handle → i

& `c` @ nurl_proc_free i handle → v

// Long-lived child with piped stdin/stdout: spawn, write, read lines,
// wait/kill, free. err_kind/last_io_err report failures; eof is 1 when
// the child's stdout closed.
& `c` @ nurl_proc_spawn s argv s cwd i merge_stderr → i

& `c` @ nurl_proc_spawn_err_kind i handle → i

& `c` @ nurl_proc_spawn_pid i handle → i

& `c` @ nurl_proc_spawn_write i handle s data i len → i

& `c` @ nurl_proc_spawn_close_stdin i handle → v

& `c` @ nurl_proc_spawn_read_line i handle i timeout_ms → s

& `c` @ nurl_proc_spawn_read_line_len i handle → i

& `c` @ nurl_proc_spawn_eof i handle → i

& `c` @ nurl_proc_spawn_last_io_err i handle → i

& `c` @ nurl_proc_spawn_wait i handle → i

& `c` @ nurl_proc_spawn_kill i handle i sig → i

& `c` @ nurl_proc_spawn_free i handle → v

// ── TCP / TLS sockets (raw) ────────────────────────────────────────
// USE stdlib/std/net.nu (+ ext/http_server.nu, std/tls.nu) — typed
// listeners, accept loops, and the pure-NURL TLS 1.3 stack sit on top
// of these.

// Listen on host:port (backlog third); returns a socket handle or <0.
// The _tls variants add PEM cert/key (and an ALPN protocol list).
& `c` @ nurl_tcp_listen s host i port i backlog → i

& `c` @ nurl_tcp_listen_tls s host i port i backlog s cert_pem s key_pem → i

& `c` @ nurl_tcp_listen_tls_alpn s host i port i backlog s cert_pem s key_pem s alpn → i

& `c` @ nurl_tcp_alpn_selected i conn → s

& `c` @ nurl_tcp_tls_add_sni i listener s host s cert_pem s key_pem → i

& `c` @ nurl_tcp_tls_reload i listener s host s cert_pem s key_pem → i

& `c` @ nurl_tcp_tls_require_client_cert i listener s ca_pem i require → i

& `c` @ nurl_tcp_peer_cert_subject i conn → s

// Accept a connection; read/write raw bytes (return byte count, <0 on
// error); close/shutdown; error kind, peer address, IO timeout (ms).
& `c` @ nurl_tcp_accept i listener → i

& `c` @ nurl_tcp_read i conn s buf i cap → i

& `c` @ nurl_tcp_write i conn s buf i len → i

& `c` @ nurl_tcp_close i conn → v

& `c` @ nurl_tcp_shutdown i conn → v

& `c` @ nurl_tcp_err_kind i conn → i

& `c` @ nurl_tcp_peer_addr i conn → s

& `c` @ nurl_tcp_set_timeout i conn i ms → v

// ── Signals, panic, recover ────────────────────────────────────────

// Install a SIGINT/SIGTERM handler that flips a shutdown flag servers
// poll (std/net.nu accept loops honor it); trigger fires it manually.
& `c` @ nurl_signal_install_shutdown i mode → v

& `c` @ nurl_signal_trigger_shutdown → v

// Abort with a message and unwind (destructors run, allocation journal
// reclaims). Catch with the `recover` language form — these are its
// runtime entry points; nurl_panic_last_msg returns the message inside
// a recover arm.
& `c` @ nurl_panic s msg → v

& `c` @ nurl_recover s fn_ptr s env_ptr → i

& `c` @ nurl_panic_last_msg → s

// libc: print a string + newline to stdout.
& `c` @ puts s text → i32

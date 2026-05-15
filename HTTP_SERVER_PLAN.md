# HTTP Server Implementation Plan

Goal: a full-featured HTTP/1.1 server in NURL — production-grade enough
to host REST APIs, the MCP HTTP/SSE transport, and the FastAPI-replacing
playground backend. Currently `Tier 4 §25` in `stdlib/STDLIB.md` and
`Tier 3 §17 (net)` are both fully unimplemented.

**Why:** unlocks (a) MCP HTTP/SSE transport (`stdlib/ext/mcp.nu` is
stdio-only today), (b) NURL-native web apps and dashboards, (c) replacing
the Python FastAPI in `api/` with a single binary, (d) webhooks for
GitHub / Stripe / Slack signature flows that the crypto module already
enables. Strategically the biggest leap from "agent host" to "full
backend host."

**Estimated total scope:** 2 000 – 3 000 LOC across 8 phases. Much of it
is independent — phases 1, 2, 3 can be parallelised.

**Status legend:** `[ ]` todo · `[x]` done

**Conventions:**
- Each phase has a clear acceptance signal (test or build outcome).
- "RT" = runtime.c addition. "NURL" = pure NURL stdlib code.
- Bootstrap fixed-point must hold after every phase (`./build.sh` green).

---

## Phase 1 — TCP socket runtime (Tier 3 §17 `net`)

Foundation. Without this nothing above accepts a connection.

### 1.1 Runtime sockets (`stdlib/runtime.c §18`) — SHIPPED 2026-05-02
- [x] `nurl_tcp_listen(host, port, backlog) → handle` (RT)
  - POSIX: `socket` + `setsockopt(SO_REUSEADDR)` + `bind` + `listen`
  - Win32: Winsock `WSAStartup` + same calls (lazy WSAStartup, idempotent)
  - WASI: every entry point stubbed to return 0 / NetOther
- [x] `nurl_tcp_accept(listener) → handle` (RT, blocking)
  - Returns a fresh NurlTcp handle; on accept failure the handle has
    err_kind set and fd == INVALID_SOCK so the wrapper can surface a
    typed NetErr without a separate sentinel value.
- [x] `nurl_tcp_read(conn, buf, n) → ssize` (RT)
  - Returns bytes read; 0 = EOF; -1 = error (sets handle err_kind).
- [x] `nurl_tcp_write(conn, buf, n) → ssize` (RT)
  - Loops over `send` until full payload written or error.
    `MSG_NOSIGNAL` on POSIX so a peer-closed socket doesn't kill the
    process via SIGPIPE.
- [x] `nurl_tcp_close(handle) → v` (RT)
- [x] `nurl_tcp_err_kind(handle) → i` — sideband per-handle error code
- [x] `nurl_tcp_peer_addr(conn) → borrowed s` — `"1.2.3.4:5678"`,
      cached on accept; lifetime tied to the handle.
- [x] `nurl_tcp_set_timeout(conn, ms) → v` — `SO_RCVTIMEO` /
      `SO_SNDTIMEO` (POSIX `struct timeval`, Win32 `DWORD ms`).

**Acceptance:** `compiler/tests/net_loopback.nu` opens listener on
loopback port 18765, spawns a backgrounded `python3` client (via
`process_run_shell`) that connects and writes "ping", the NURL server
`accept`s + `read`s "ping" + writes "pong", client reads "pong" back.
Gated by `NURL_NET_TESTS=1`. Verified ASan-clean (no leaks / use-
after-free / out-of-bounds).

### 1.2 NURL wrapper (`stdlib/std/net.nu`) — SHIPPED 2026-05-02
- [x] `: TcpListener { s raw }` opaque handle (s-cast i64 like Output / Response)
- [x] `: TcpConn     { s raw }` opaque handle
- [x] `: NetErr` enum (`NetBind | NetAddrInUse | NetAccept | NetRead | NetWrite | NetClosed | NetTimeout | NetOther`)
- [x] `tcp_listen s host i port → ! TcpListener NetErr` — backlog=128
- [x] `tcp_listen_with_backlog s host i port i backlog → ! TcpListener NetErr`
- [x] `tcp_accept TcpListener → ! TcpConn NetErr`
- [x] `tcp_read_chunk TcpConn i max → ! ( Vec u ) NetErr` — one
      `recv(2)`, owned Vec[u] result. Clean EOF surfaces as
      `NetClosed` so empty Ok-vectors are unambiguous.
- [x] `tcp_write_all TcpConn ( Vec u ) → ! v NetErr` — loops until done
- [x] `tcp_write_str TcpConn s → ! v NetErr` — convenience for ASCII headers
- [x] `tcp_close_listener TcpListener → v`
- [x] `tcp_close_conn TcpConn → v`
- [x] `tcp_peer_addr TcpConn → s` (borrowed; copy with `string_from`)
- [x] `tcp_set_timeout TcpConn i ms → v`
- [x] `net_err_name NetErr → s`

**Acceptance:** `compiler/tests/net_basic.nu` (unconditional)
exercises every NetErr variant name + the listen error paths
(port 0, malformed host) without opening any real socket.
`compiler/tests/net_loopback.nu` (gated by `NURL_NET_TESTS=1`)
covers the full live round-trip.

### 1.3 Concurrency primitive prerequisite — pick ONE
The simplest server (Phase 4) is single-threaded. But anything realistic
needs concurrent connection handling. Decide before Phase 5:

- [ ] **Option A: pthread/Win32 thread-per-connection.** Match the
      pattern already in use by `process.nu` (Win32 reader-threads).
      Adds: `nurl_thread_spawn(fn, env) → handle`, `nurl_thread_join`,
      `nurl_mutex_*`, `nurl_cond_*`. ~150 LOC runtime. Simplest mental
      model.
- [ ] **Option B: epoll/kqueue/IOCP event loop.** Single-threaded async
      I/O. ~400 LOC runtime, complex callback ABI question (same
      closure-ABI obstacle that streaming hit). High performance but
      hard to debug.
- [ ] **Option C: pre-fork worker pool.** POSIX-only; one master, N
      worker processes via `fork`. Reuses existing `process.nu`
      machinery. No threading model needed. Doesn't work on Windows.

**Recommendation:** Option A (thread-per-connection) for Phase 5 —
matches the streaming work and process.nu's already-proven Win32 thread
usage; portable across all targets we care about.

---

## Phase 2 — HTTP/1.1 request parser (`stdlib/ext/http_request.nu`) — SHIPPED 2026-05-02

Pure NURL. No socket dependency for the parser proper — accepts a
`( Vec u )` byte buffer and yields a parsed Request. Body reader
(`read_body`) layers on top of `std/net.nu` once a TcpConn is available.

### 2.1 Request line + headers — SHIPPED 2026-05-02
- [x] `: HttpRequest { String method, String path, String query, String version, ( Vec Header ) headers, ( Vec u ) body }`
- [x] `: HttpReqErr` enum: `HttpReqMalformed | HttpReqTooLarge | HttpReqUnsupportedVersion | HttpReqIncomplete | HttpReqIo`
- [x] `parse_request_head ( Vec u ) buf → ParsedHead`
  - **Note:** signature ended up returning a tagged-struct ParsedHead
    rather than `! ParsedHead HttpReqErr`. The Result encoding `{ i1, i64
    }` only fits `T` values that pack into i64 — multi-field structs
    miscompile. See "Cross-cutting prerequisites" entry below.
  - Caller branches on `.ok`; on success reads `.head` + `.consumed`,
    on failure reads `.err`. `parsed_head_free` is empty-safe so a
    single free call works for both arms.
- [x] Header folding: combine `Foo: a` then `Foo: b` into `Foo: a, b` per
      RFC 7230 §3.2.2.
- [x] Case-insensitive header lookup: `header_get ( Vec Header ) hs s name → ? String`.
- [x] Limits: max 8 KB head, max 100 headers — return `HttpReqTooLarge`.

### 2.2 URL + query parser — SHIPPED 2026-05-02
- [x] `parse_url s url → UrlSplit` — `{ String path, String query }`
- [x] `parse_query s query → ( Vec QueryPair )` — `&`-separated, percent-decode
- [x] `percent_decode s in → String` — `%20` → ` ` etc., honours `+` → space
- [x] `percent_encode s in → String` — RFC 3986 unreserved set, uppercase hex
  - **Note:** `UrlSplit` and `QueryPair` are dedicated structs rather
    than `Pair[String,String]` because the compiler currently doesn't
    accept compound type-args in the `( Vec ( Pair K V ) )` form (return
    / declaration positions). The slice form `[( Pair K V )]` works.
    See "Cross-cutting prerequisites" entry below.

### 2.3 Body reading — SHIPPED 2026-05-02
- [x] Content-Length path: read N bytes from socket, append to body Vec[u]
- [x] Chunked transfer-encoding: parse `\r\n`-prefixed hex sizes,
      append payload until `0\r\n\r\n`. RFC 7230 §4.1.
- [x] `read_body TcpConn HttpRequest → ! ( Vec u ) HttpReqErr`
      (`( Vec u )` is single-field, fits the Result encoding fine)
- [x] `read_body_to TcpConn HttpRequest i max_bytes → ! ( Vec u ) HttpReqErr`
- [x] Limit: configurable max body size (default 10 MB → `HttpReqTooLarge`)

**Acceptance:** `compiler/tests/http_request_parser.nu` feeds synthetic
buffers (well-formed GET, well-formed POST + multi-header folding,
percent-encoded query, unsupported version, incomplete head, malformed
request line, oversized head). All four parser-error variants
exercised. ASan-clean (no leaks / use-after-free / out-of-bounds).
Test runs unconditionally — it's pure-parser, no socket dependency, so
gated alongside `net_basic.nu` in `run_tests.{sh,bat}`.

---

## Phase 3 — HTTP/1.1 response writer (`stdlib/ext/http_response.nu`) — SHIPPED 2026-05-02

Pure NURL. `response_serialize` builds a `( Vec u )` containing a
complete HTTP/1.1 response; `response_begin_chunked` / `_write_chunk`
/ `_end_chunked` stream directly to a TcpConn for SSE.

### 3.1 Response builder — SHIPPED 2026-05-02
- [x] `: HttpResponse { i status, ( Vec Header ) headers, ( Vec u ) body }`
- [x] `response_new i status → HttpResponse`
- [x] `response_set_header HttpResponse s name s value → v` (always
      appends; HTTP/1.1 permits multi-valued Set-Cookie / Vary / Link)
- [x] `response_set_body_str HttpResponse s text → v`
- [x] `response_set_body_bytes HttpResponse ( Vec u ) → v`
- [x] `response_set_body_json HttpResponse Json → v` (auto-sets
      `Content-Type: application/json; charset=utf-8` if not pinned)
- [x] Helpers: `response_text`, `response_json`, `response_redirect`,
      `response_status_only`, `response_error`
- [x] `response_serialize HttpResponse → ( Vec u )` — status line +
      headers + auto Content-Length (unless TE/CL already pinned) +
      blank line + body
- [x] `http_response_free` (renamed from `response_free` to avoid
      collision with `http.nu`'s client-side `Response` cleanup)

### 3.2 Status code table — SHIPPED 2026-05-02
- [x] `status_reason i code → s` — borrowed raw `s`, covers 35+ codes
      across 1xx/2xx/3xx/4xx/5xx per RFC 7231; unknown codes get
      "Unknown" so the wire stays parseable.

### 3.3 Streaming response (chunked) — SHIPPED 2026-05-02
- [x] `response_begin_chunked TcpConn i status ( Vec Header ) hs → ! v NetErr`
      (forces `Transfer-Encoding: chunked`, suppresses any caller-supplied
      TE/CL header)
- [x] `response_write_chunk TcpConn ( Vec u ) → ! v NetErr` — wraps in
      `<hex>\r\n<bytes>\r\n`; empty Vecs are silently skipped
- [x] `response_end_chunked TcpConn → ! v NetErr` — sends `0\r\n\r\n`
- [x] **Required for** SSE responses (MCP HTTP/SSE transport, server-sent
      events to browsers). Cross-cutting `__append_hex_size` helper
      formats lowercase hex sizes per RFC 7230 §4.1.

**Acceptance:** `compiler/tests/http_response_builder.nu` (unconditional)
builds 7 stock responses (`response_text 200`, `response_status_only 204`,
`response_redirect 302`, `response_error 404`, `response_json 200`,
manual+custom-header 201, pinned Content-Length 200), serialises each,
and verifies the expected wire bytes via a CR/LF-translating dumper
against a golden `correct.txt` baseline. `status_reason` table sampled
across 1xx-5xx + unknown. ASan-clean. Live chunked-streaming test is
deferred to Phase 4 (loopback) — it requires a real TcpConn round-trip.

---

## Phase 4 — Single-threaded server skeleton (`stdlib/ext/http_server.nu`) — SHIPPED 2026-05-02

Sequential connection handling — accept one, serve, close, accept next.
Acceptable for low-traffic local services (MCP transport, dev playground,
internal dashboards). Concurrency arrives in Phase 5.

- [x] `: HttpServer { TcpListener listener, (@ HttpResponse HttpRequest) handler }`
- [x] `server_new TcpListener (@ HttpResponse HttpRequest) handler → HttpServer`
  - **Note:** the spec called for `i port → ! HttpServer NetErr`, but
    HttpServer is multi-field (listener handle + closure value), and
    Result Ok arms can't carry multi-field values today. Splitting
    listening from server-construction is the workaround: caller does
    `tcp_listen`, then `server_new`. Cleaner anyway — the failure mode
    is the listen step, not the bundle step.
- [x] `server_run_once HttpServer → ! v NetErr` (single connection)
- [x] `server_run HttpServer → ! v NetErr` (loops `_once` until clean
      stop or fatal error). NetClosed/NetAccept post-stop maps to Ok.
- [x] Error responses: malformed head produces a stock 400, oversized
      → 413, unsupported version → 505 — no socket-level crash.
- [x] `Connection: close` honored — `__write_response` injects the
      header if the handler didn't already set it.
- [x] `server_stop HttpServer → v` — closes listener.
- [x] Read loop transfers any pre-loaded body bytes (delivered in the
      same TCP segment as the head) into `req.body` before
      `__finish_body` tops up via Content-Length.

**Acceptance:** `compiler/tests/http_server_seq.nu` (gated behind
`NURL_NET_TESTS=1`) starts a server on `127.0.0.1:18766`, spawns
`curl` in a background shell that POSTs `hello srv` with header
`X-From: nurl-test`, runs `server_run_once` so the echo handler
captures method/path/version/body, writes the response back. Test
verifies curl saw the echo body and a successful round-trip. ASan-clean.
Stress / 100-concurrent-curl test deferred to Phase 5 (needs threads).

**MVP MILESTONE:** the first end-to-end NURL HTTP server is alive.
Demo: `( server_run_once srv )` answers a `curl` POST with the echoed
request. The "single binary, no curl" web stack is now feasible —
remaining Phase 5+ work is concurrency, routing, and hardening.

### Phase 4 — Cross-cutting fix
- [x] `MAX_LEX 256 → 1024` in `stdlib/runtime.c` (compiler-internal
      lexer pool). The transitive `$`-include chain through
      net + bytes + string + vec + http + http_request +
      http_response + http_server overflowed the 256-slot pool. 1024 ×
      ~80 B = ~80 KB, fine for the user-program runtime image too.

---

## Phase 5 — Concurrency (thread-per-connection)

Promotes the server from "toy" to "actually usable." Picks Option A
from Phase 1.3.

### 5.1 Thread runtime (`stdlib/runtime.c §19`) — SHIPPED 2026-05-06
- [x] `nurl_thread_spawn(fn, env) → handle` (RT)
  - POSIX: `pthread_create` + small NurlThread struct (handle + fn + env)
  - Win32: `_beginthreadex` (matches `process.nu`'s reader-thread style)
  - Returns 0 on creation failure; otherwise an i64-cast NurlThread*
    that the wrapper converts into `Thread { s raw }`.
- [x] `nurl_thread_join(handle) → i` (RT) — blocks, frees handle
- [x] `nurl_thread_detach(handle) → v` (RT) — fire-and-forget worker
- [x] `nurl_mutex_new → handle`, `_lock`, `_unlock`, `_free` (RT)
  - POSIX: `pthread_mutex_t`. Win32: `CRITICAL_SECTION`
- [x] `nurl_cond_new → handle`, `_wait`, `_signal`, `_broadcast`, `_free` (RT)
  - POSIX: `pthread_cond_t`. Win32: `CONDITION_VARIABLE` +
    `SleepConditionVariableCS`
- [x] WASI: every entry returns 0/-1 stubs (serial fallback)

### 5.2 NURL surface (`stdlib/std/thread.nu`) — SHIPPED 2026-05-06
- [x] `: Thread { s raw }`, `: Mutex { s raw }`, `: Cond { s raw }`
      (single-pointer handles, same convention as `TcpListener` /
      `TcpConn` — `i raw` would force every wrapper into a `# i`
      round-trip; `s raw` keeps them naturally pointer-shaped.)
- [x] `thread_spawn ( @ v ) f → ! Thread ThreadErr` — closure ABI
      via the closure-field-extract `#`-cast (see Cross-cutting
      prerequisites; landed in same session).
- [x] `thread_join Thread → i`, `thread_detach Thread → v`
- [x] `mutex_new`, `mutex_lock/_unlock/_free`,
      `mutex_with Mutex (@ v) body → v` (lock + run + unlock helper)
- [x] `cond_new`, `cond_wait Cond Mutex → v`, `cond_signal/_broadcast/_free`
- [x] `ThreadErr { ThreadCreate | ThreadOther }` + `thread_err_name`
- [x] `: Channel` — i64-slot FIFO on top of mutex + cond + `( Vec i )`
      (`stdlib/std/channel.nu`, shipped 2026-05-06). Generic
      `Channel[T]` deferred until nested-generic instantiation
      propagates through `scan_generic_structs`; the i64-channel is
      sufficient for `Channel[TcpConn]` (cast `s raw` ↔ `i` in/out)
      and primitive-typed pipelines.
- [x] `chan_new`, `chan_send`, `chan_recv`, `chan_try_recv`,
      `chan_close`, `chan_len`, `chan_is_closed`, `chan_free`
      (all in `stdlib/std/channel.nu`)

**Open question RESOLVED 2026-05-06:** option 1 (compiler builtin,
`#`-cast extension) shipped. Syntax: `# *u closure 0` extracts the
fn pointer, `# *u closure 1` extracts the env pointer — both as raw
`*u` (i8*) values, ready to feed any C runtime callback API. Trigger
condition: src type matches closure shape (`{ R (i8*…)*, i8* }`),
dst is a pointer, next lexer token is INT 0 or 1. Implementation is
~35 LOC in `gen_cast` (`compiler/nurlc.nu`); emits `extractvalue` plus
an optional `bitcast` when dst differs from the field's natural type.
Used by `thread_spawn` today; reusable for any future signal-handler /
GTK-callback / atexit interop.

### 5.2.1 Memory model — closure lifetime (SHIPPED, documentation note)

`thread_spawn` BORROWS the closure value and the captured env pointer
it carries. The closure (and any heap allocations its env points at)
MUST OUTLIVE the worker thread; typical pattern is to hold the closure
in a local binding and `thread_join` before that binding goes out of
scope. NURL has no exception model, so there's no way for an inner
panic to skip the join — the caller must structure the code so a
joined thread is guaranteed before the captured state is dropped.

### 5.3 Server integration
- [x] **`server_run_pool HttpServer i n_workers → ! v NetErr`** shipped
      2026-05-06. Spawns N worker threads, each calls `server_run_once`
      in a loop against the SHARED listener (kernel-serialised accept —
      both POSIX accept(2) and Win32 accept are thread-safe). When the
      listener is shutdown (caller-side, typically from another thread
      or signal handler), every worker's accept returns
      `NetClosed` / `NetAccept` and the worker exits its loop.
      `server_run_pool` joins all workers and returns Ok(0).
      `n_workers ≤ 1` short-circuits to plain `server_run`.
      Closure-captures the HttpServer struct (multi-field — handler
      closure + listener handle); validates the
      closure-aggregate-capture path end-to-end. Worker storage is a
      raw `nurl_alloc(n*8)` byte buffer of i64 thread handles
      (Vec[Thread] would need multi-field-struct generic
      instantiation that isn't yet wired).
- [x] **`tcp_shutdown_listener`** + runtime `nurl_tcp_shutdown` (split
      from `nurl_tcp_close`, shipped 2026-05-06): closes the kernel FD
      WITHOUT freeing the NurlTcp struct. Required because closing the
      socket while worker threads are blocked in accept races against
      their post-accept dereference of `h->err_kind` — observed as
      ~40% intermittent SIGSEGV at process exit on Windows. Caller's
      shutdown thread uses `tcp_shutdown_listener` to wake workers,
      then after `server_run_pool` joins, the caller invokes
      `server_stop` (which calls `nurl_tcp_close`, full free) exactly
      once. Documented as the canonical shutdown protocol in
      `compiler/tests/http_server_pool.nu`.
- [x] **Keep-alive — SHIPPED 2026-05-07 (Phase 5.4):** same connection
      serves multiple requests until `Connection: close`, idle timeout
      (default 30 s), or the per-conn `max_keepalive_requests` cap
      (default 1000). `server_run_once` walks a `__serve_keepalive_loop`
      that performs request → handler → response until any of those
      fires. Bench: 100 sequential `/api/health` requests dropped from
      5152 ms → 136 ms (~38× speedup) on the canonical
      `examples/static_server.nu`.
- [x] **Pipelining correctness — SHIPPED 2026-05-15:** request framing
      now survives the pipelined case where a client puts req2 in the
      same `send()` as req1 (HTTP/1.1 §6.3.2). `__serve_keepalive_loop`
      owns a connection-level `Vec[u] carry` buffer that survives
      across iterations; `__read_request_head` reads into carry and
      drops only the consumed-by-the-head bytes after a successful
      parse; `__finish_body` drains exactly Content-Length bytes off
      carry's front before topping up from the socket. The previous
      design stuffed all trailing bytes wholesale into `req.body`,
      which silently corrupted req1's body AND dropped req2 entirely
      (the next iteration's fresh-buf read saw the socket empty).
      Acceptance: `compiler/tests/http_server_pipelined.nu` sends two
      POSTs in one TCP `sendall` and verifies both handler
      invocations + both responses. We do NOT promise out-of-order
      pipelined-response delivery (the spec doesn't require it) —
      responses ride the same TCP stream in request order.
- [ ] **Stress acceptance test:** 100 concurrent curl connections, all
      return 200, ASan-clean. Deferred to Phase 8 hardening sprint —
      MVP test (`compiler/tests/http_server_pool.nu`) covers the
      lifecycle (spawn / join / shutdown) but the at-exit Win32
      cleanup race needs a proper barrier.

**Known limitation (Win32 at-exit race):** `compiler/tests/http_server_pool.nu`
exhibits ~10–40% SIGSEGV at PROCESS EXIT after a successful pool
shutdown ("pool: clean shutdown" always prints first). Likely the
WinHTTP / Winsock / CRT atexit interaction — needs investigation. The
pool itself is functional; the race is purely in final cleanup. Phase
8 graceful-shutdown work will replace the soft-close + join + close
pattern with a proper barrier.

---

## Phase 6 — Routing + middleware (`stdlib/ext/http_router.nu`) — SHIPPED 2026-05-05

- [x] `: Router { ( Vec Route ) routes }` where `Route { String method, String pattern, (@ HttpResponse HttpRequest Params) handler }`
- [x] `: Params { ( Vec QueryPair ) entries }` — path captures.
      Backed by `QueryPair` from `http_request.nu` (rather than a fresh
      `Pair[String,String]`-typed Vec) so `params_get` mirrors
      `header_get`'s shape — returns `? String` with an OWNED copy in
      the Some arm. Naming: `params_get` instead of the spec's
      `param_get` to match the existing `params_count` / `params_free`
      helpers.
- [x] `router_new → Router`
- [x] `router_get/post/put/patch/delete Router s pattern handler → v` (mutates)
- [x] `router_any Router s method s pattern handler → v` — explicit
      method, `"*"` matches any.
- [x] Pattern matching: literal segments + named captures (`/users/:id`).
      Strict trailing-slash semantics (`/foo` ≠ `/foo/`); empty path
      segments don't match `:name`.
- [x] Wildcard tail: `/static/*path` captures the rest, INCLUDING any
      embedded slashes. Must be the final pattern segment.
- [x] `router_handle Router HttpRequest → HttpResponse` — linear scan,
      first match wins; falls back to a stock `response_text 404 "not
      found\n"`. Returns HttpResponse directly (not `! T E`) since
      multi-field structs still can't ride Result Ok arms.
- [x] `params_get Params s key → ? String` (case-sensitive lookup,
      mirrors `header_get`'s OWNED-string convention).
- [x] Middleware as handler-wrapping combinators:
      - `with_log_requests inner → wrapped` — logs `[req] METHOD path` +
        `[req] METHOD path → STATUS` to stderr.
      - `with_cors_default inner → wrapped` — adds permissive CORS
        headers and short-circuits OPTIONS preflight to 204.
      Composition is left-to-right at call site
      (`with_log_requests (with_cors_default base)`); no `Vec[Middleware]`
      registry inside the Router.
  - **Note on chosen middleware shape:** the spec called for a
    `(@ HttpResponse HttpRequest (@ HttpResponse HttpRequest) next)`
    closure type stored in a `Vec[Middleware]`. That works at the
    declaration level but `Vec[Middleware]` of a closure-shaped struct
    runs into the same multi-field `vec_get` miscompile as
    `Vec[Header]`. Handler-level combinators avoid the registry
    entirely and compose by closure capture (already-proven path).
    `panic_recovery → 500` deferred to Phase 8 — needs a NURL-level
    panic / signal hook that doesn't exist yet.

**Acceptance:** `compiler/tests/http_router.nu` (unconditional, no
socket — gated alongside `http_request_parser` / `http_response_builder`
in `run_tests.{bat,sh}`) covers 14 dispatch cases: static literals,
single + double named captures, wildcard tail (single segment + deep
nested), method dispatch (GET vs POST same path), `*`-method match,
404 fallback (no path / method mismatch / trailing slash / empty
segment), `params_get` hits + miss, plus middleware composition (200
GET round-trip with CORS headers + OPTIONS preflight short-circuit to
204 with Allow-Methods). Build fixed-point holds. **Strategic
milestone reached:** MCP HTTP/SSE transport now blocks only on
calling `response_begin_chunked` / `response_write_chunk` from a
`router_post "/messages"` handler — every needed primitive exists.

---

## Phase 7 — Conveniences

Optional but expected.

- [ ] `serve_static String dir HttpRequest → ? HttpResponse` — security:
      reject `..` segments, follow symlinks only inside dir
- [ ] `mime_for_ext s ext → s` — table covering common types (html, css,
      js, json, png, jpg, svg, woff2, …)
- [ ] Cookie helpers: `request_cookie HttpRequest s name → ? String`,
      `response_set_cookie HttpResponse s name s value Cookie opts → v`
      (path/domain/secure/httponly/samesite/max-age)
- [ ] Form parsing: `parse_form_urlencoded ( Vec u ) → ( Vec ( String , String ) )`
      (multipart/form-data deferred to Phase 9 — needs a separate parser)
- [ ] Compression: `Accept-Encoding: gzip` → wrap body in
      runtime gzip (deferred — needs `nurl_gzip_*` runtime, libz)
- [ ] Auth helpers: `parse_basic_auth Header → ? ( String user, String pass )`,
      `parse_bearer_auth Header → ? String`

---

## Phase 8 — Production hardening

- [ ] Graceful shutdown: signal handler closes listener + drains
      in-flight workers within N seconds, then `_exit`.
- [ ] Per-request timeout (idle + total).
- [ ] Slowloris defence: header-read deadline + max idle time.
- [ ] Request size limits (head + body), configurable per-server.
- [ ] Header count limit (default 100).
- [x] **Handler panic recovery — SHIPPED 2026-05-15** (closes Phase 8
      end-to-end). New panic model in `stdlib/std/panic.nu`:
      `panic s msg → v` for explicit aborts, `recover ( @ v ) closure
      → ! v PanicInfo` for setjmp/longjmp-based catch. Built on
      `nurl_recover` / `nurl_panic` / `nurl_panic_last_msg` runtime
      primitives (thread-local jmp_buf stack). `__serve_keepalive_loop`
      wraps the handler call in `recover`; on panic, logs the captured
      message to stderr via `nurl_eprintln` and substitutes a stock 500
      "internal server error" response. Worker thread keeps running —
      next accept proceeds normally. v1 cost model: owned heap
      allocations made inside the handler that didn't run their auto-
      drop LEAK; signal faults (SIGSEGV/SIGFPE/SIGBUS/SIGABRT) are NOT
      caught (kept as process aborts, async-signal-safety constraints).
      Regression: `compiler/tests/recover_basic.nu` (offline — Ok arm,
      Err arm, multi-field-struct typed return via byref-capture) and
      `compiler/tests/http_server_panic.nu` (NURL_NET_TESTS=1 — handler
      panic → 500 on the wire, server alive after).
- [ ] Access log middleware (NCSA combined or JSON, env-toggleable).
- [ ] Metrics middleware (Prometheus-shaped `/metrics` endpoint via
      simple counter map).

---

## Phase 9 — Optional / later

- [x] **TLS via libssl/OpenSSL — SHIPPED 2026-05-15 (server-side).**
      `nurl_tcp_listen_tls(host, port, backlog, cert_path, key_path)`
      in `stdlib/runtime.c` composes the plain socket listen with an
      `SSL_CTX` configured from PEM cert + private-key files (TLS 1.2
      minimum). `NurlTcp` gained two optional fields (`SSL *ssl`,
      `SSL_CTX *ssl_ctx`) that make the handle polymorphic —
      `nurl_tcp_read` / `_write` / `_close` dispatch via libssl when
      `ssl` is set. HttpServer and every existing TcpConn consumer get
      HTTPS without code changes — callers just swap
      `tcp_listen` → `tcp_listen_tls`. Build-time dependency detected
      via `pkg-config --exists openssl` in `build.sh` (mirrors libcurl
      pattern); when absent, every TLS call returns `NetTlsCtxInit`.
      NURL surface: `tcp_listen_tls` / `_with_backlog` in
      `stdlib/std/net.nu`; new `NetErr` variants `NetTlsCtxInit` /
      `NetTlsCertLoad` / `NetTlsKeyLoad` / `NetTlsHandshake`. v1 scope
      deferred for later: no SNI (single cert per listener), no ALPN,
      no client-cert auth, no live cert reload, no session-resumption
      tuning. Regression: `compiler/tests/http_server_tls.nu`
      (NURL_NET_TESTS=1) — generates a self-signed cert at runtime
      via `openssl req`, runs `server_run_once` with TLS, verifies an
      HTTPS GET round-trips correctly through python's
      `ssl.create_default_context()`-wrapped client.
- [ ] **HTTP/2.** Major undertaking — separate planning doc.
- [ ] **WebSocket upgrade.** Frame parser + writer; reuse Phase 1
      sockets. Probably ~400 LOC.
- [ ] **Multipart/form-data.** Boundary-delimited parser; needed for
      file uploads.
- [x] **Reverse-proxy / streaming pass-through — SHIPPED 2026-05-07:**
      `stdlib/ext/http_proxy.nu`. Wires libcurl multi streaming
      (runtime §14b) into the chunked response writer — every upstream
      chunk is flushed straight to the client. Surface:
      `proxy_stream_to_conn[_with]` (streams from a TcpConn against a
      fixed upstream URL), `proxy_serve_run[_with]` (dedicated accept
      loop). Filters RFC 7230 §6.1 hop-by-hop headers both directions;
      strips `Content-Length` and `Content-Encoding` on response (libcurl
      auto-decompresses; we re-encode chunked). Runtime grew
      `nurl_http_stream_pump_headers` + `_header_count`/`_name`/`_value`;
      compiler emits decls in the runtime preamble. Buffered (`!
      HttpResponse HttpErr`) path intentionally not exposed — multi-
      field-struct payloads inside `! T E` trip a compiler heap-boxing
      bug. Streaming is the only mode AI gateways need anyway.

---

## Strategic milestones

These are the externally visible "we shipped something" moments:

- [x] **MVP (after Phase 4) — SHIPPED 2026-05-02:** single-threaded
      server can answer a POST and echo the request fields. Demoable.
      Not production-ready until Phase 5 brings concurrency + Phase 8
      brings hardening.
- [x] **Routing layer (Phase 6) — SHIPPED 2026-05-05:** method + path
      routing with named captures and tail wildcards, plus
      handler-wrapping middleware combinators. Now writing a multi-
      route web app is `router_get` / `router_post` over a Router
      handed to `server_new` as the dispatch closure. Unblocked MCP
      HTTP/SSE — every primitive needed (chunked streaming + routing)
      exists.
- [x] **MCP HTTP shipped (after Phases 4 + 3.3 + Phase 6) — SHIPPED
      2026-05-05:** `stdlib/ext/mcp_http.nu` provides
      `mcp_http_handler dispatch → ( @ HttpResponse HttpRequest )`
      and `mcp_server_run_http host port dispatch → ! v NetErr`.
      Tools-only servers (stateless, request/response only) are
      drop-in: `examples/mcp_echo_server_http.nu` echoes via
      `curl -X POST http://127.0.0.1:18770/mcp ...`. Server-pushed
      notifications via GET-SSE deferred (non-blocking — the chunked
      streaming primitives from Phase 3.3 are already in place; just
      needs a notification queue).
- [ ] **FastAPI replacement shipped (after Phases 5 + 6):** `api/` Python
      backend rewritten in NURL. Single binary, ~100x smaller image,
      same playground UX. STDLIB.md §25 closes.
- [ ] **Production-ready (after Phases 7 + 8):** the 80% feature parity
      with mainstream microframeworks (Express, Sinatra, FastAPI). Safe
      to recommend for real services.

---

## Cross-cutting prerequisites

These must land at SOME point in the above; calling them out so they
aren't lost in a sub-phase:

- [x] **Compiler: compound type-args in `parse_type_paren`** (shipped
      2026-05-04). `parse_type_paren` and `scan_generic_structs` now
      recurse on `TT_LPAREN` in their type-arg loops via the new
      `scan_compound_ta_inner` helper, which consumes a nested
      `( Name T1 T2 ... )` group, triggers
      `ensure_struct_instantiated` for the inner generic, and returns
      the mangled fragment as a single ident-shaped ta_list element.
      `( Vec ( Pair s i ) )`, `( Vec ( Pair s String ) )`, struct
      fields and locals all work uniformly. Test: `compound_type_args.nu`
      (Vec[Pair[s,i]] in fn return, locals, and struct field — ASan-clean).
      Tparam-only compound ta in generic signatures is still out of
      scope (would need `is_tparam_like` to recognise compound forms).
- [x] **Compiler: multi-field structs as `! T E` Ok arm** (shipped
      2026-05-04). The Result encoding stays `{ i1, i64 }`; multi-field
      `T` is now heap-boxed transparently. `gen_agg_lit`'s struct branch
      detects `f0` is non-pointer (the multi-field signature, since
      single-handle structs have an i8* f0) and emits
      `nurl_alloc(sizeof T) → store T → ptrtoint to i64` into the
      payload slot. `gen_match`'s struct reconstruction path mirrors:
      `inttoptr i64 → %T* → load %T → free`. `! ParsedHead HttpReqErr`,
      `! HttpRequest HttpReqErr`, `! Tagged ParseErr` etc. now compile
      and round-trip cleanly. Test: `result_multifield.nu` (Pt2,
      Quad, Tagged{String,i} — both Ok and Err arms, ASan-clean).
      **Still TODO:** (a) Option `? T` Some arm for multi-field T
      (encoding is `{ i1, T }` — storage is fine; default-construct
      None side via memset/zeroinit needs `gen_cast`/`# A 0`-default
      patch). (b) `vec_get [MultiFieldStruct]`, `vec_pop`, `option_*`
      combinators returning multi-field T — same default-construct
      issue. Phase 2 workaround (direct `*A` pointer iteration via
      `vec_data`) remains in place.
- [x] **Compiler: closure-field-extraction `#`-cast** (Phase 5.2 open
      question, shipped 2026-05-06). `gen_cast` now detects the
      closure-source + pointer-dst + INT-0/1-next pattern and emits
      `extractvalue` + bitcast. ~35 LOC in `compiler/nurlc.nu`. Test
      coverage via `compiler/tests/thread_basic.nu`'s `thread_spawn`
      path. Reusable for any future C-callback interop.
- [x] **Runtime: thread + mutex + cond primitives** (Phase 5.1, shipped
      2026-05-06). `stdlib/runtime.c §19` adds POSIX (pthread_*) and
      Win32 (`_beginthreadex` + `CRITICAL_SECTION` +
      `CONDITION_VARIABLE`) backends; WASI degrades to no-op stubs.
      Same opaque-i64-handle convention as `process.nu` / `net.nu`.
- [x] **Runtime: `setsockopt` portability layer** (Phase 1.1 shipped 2026-05-02).
      `SO_REUSEADDR` and `SO_RCVTIMEO`/`SO_SNDTIMEO` already wired across
      POSIX (`struct timeval`) and Win32 (`DWORD ms`). `TCP_NODELAY` is
      deferred — add when the server starts batching small writes.
- [x] **Build system: `-lpthread` on Linux** (Phase 5.1, shipped
      2026-05-06). `build.sh` (3× link steps), `nurl.sh` (final user
      link) and `compiler/tests/run_tests.sh` (per-test link) all
      append `-lpthread` next to the existing `-lm`. Windows uses the
      Win32 thread API natively (no extra link flag needed beyond what
      `-lwinhttp` already pulls in).
- [ ] **Build system: optional `-lcurl` removal in pure-server builds.**
      The HTTP server doesn't need libcurl. Don't break existing client
      callers.
- [x] **Stdlib: `vec_set_len [A] v n` helper** (`stdlib/core/vec.nu`,
      shipped 2026-05-02). General-purpose primitive for FFI-driven
      buffer fills: caller pre-sizes a Vec via `vec_with_cap`, hands the
      `vec_data` pointer to the runtime, then commits the actual bytes-
      written via `vec_set_len`. Used by `tcp_read_chunk`; reusable for
      binary file IO, hash-digest sinks, and any future Vec[u] FFI.
- [ ] **Documentation: `examples/http_hello.nu`** — minimal demo (5–10
      lines) shipped with Phase 4. Becomes the canonical "designed for
      LLMs" sample for the README.

---

## Why this order matters

1. **Phases 1–3 are independent** and could be done in parallel. The
   recommended order is 1→2→3 because socket primitives are foundational
   and parser/writer can be tested via static buffers before the socket
   is ready.
2. **Phase 4 is the demoable milestone** — without it nothing earlier
   has visible UX.
3. **Phase 5 (threads) is a hinge** — postponing it traps the server in
   "toy" status. Doing it after Phase 4 means the threading code can be
   tested against a working server.
4. **Phases 6–8 are layers** that compose. Each phase is shippable
   without the next.
5. **Phase 9 items are intentionally deferred** — they each have their
   own design story, and v1 of the server is genuinely useful without
   them.

---

## Existing code that informs this plan

- `stdlib/runtime.c §16` (`nurl_proc_run` POSIX `fork`/`pipe`/`poll` +
  Win32 `CreateProcess` with reader threads) — sets the pattern for
  blocking IO + threads. Phase 1.1 + 5.1 should follow this style.
- `stdlib/runtime.c §14` (HTTP client + libcurl) — sets the
  request/response struct pattern. Phase 2/3 mirror it for the server
  side.
- `stdlib/runtime.c §14b` (HTTP streaming, just shipped) — sets the
  pull-based handle + opaque-int pattern. Phase 1.2 reuses this for
  TcpConn.
- `stdlib/ext/mcp.nu` — primitive-only design (no built-in registry).
  Phase 6 routing should match: high-level convenience helpers built
  from primitives, not a monolithic framework.
- `compiler/nurlc.nu#call_closure_function` — already does
  `extractvalue 0/1` on closure structs. The Phase 5 compiler change
  exposes this as syntax.

---

*Last updated: 2026-05-05 — **MCP HTTP transport shipped** in
`stdlib/ext/mcp_http.nu` (~210 LOC pure NURL on top of Phases 1–4 + 6;
no runtime/compiler additions). **Pinta:** `mcp_http_handler dispatch
→ ( @ HttpResponse HttpRequest )` (drop-in for `server_new` or
wrapped for `router_post`) + `mcp_server_run_http host port dispatch
→ ! v NetErr` (one-line listen+serve). **Method matrix:** POST →
parse JSON → dispatch → 200 application/json (or 202 if dispatch
returns None for notifications); GET → 405 (SSE-stream MVP-deferred);
DELETE → 204 (stateless); OPTIONS → 204 + permissive CORS preflight.
**JSON-RPC error envelopes** (per spec) ride HTTP 200: parse_error
(-32700) for malformed JSON body, invalid_request (-32600) for empty
body. Permissive CORS auto-applied to every response — claude.ai and
other browser-based MCP clients work without bespoke middleware.
Dispatch shape mirrors the stdio `handle` from
`examples/mcp_echo_server.nu` exactly: stdio→HTTP migration of an
existing tools server is ~5 lines of adapter code (return `? Json`
instead of `mcp_send_message`). Test
`compiler/tests/mcp_http.nu` (12 cases, ~250 lines, unconditional
non-network — pure offline handler exercise) snapshots every status
code and body byte across initialize / notifications / ping /
tools_list / tools_call / unknown_method / malformed_json /
empty_body / GET-405 / DELETE-204 / OPTIONS-204+CORS / PUT-405.
Example `examples/mcp_echo_server_http.nu` (~150 lines, identical
business logic to `mcp_echo_server.nu` minus the framing layer)
listens on `127.0.0.1:18770/mcp` and answers
`curl -X POST ...`. Build fixed-point preserved. **Strategic
milestone closed:** STDLIB.md §33 "HTTP/SSE-transport ja
Streamable-HTTP" todo done (sans GET-SSE — easy follow-on, all
primitives in place); LLM-agenttihost-tarina is symmetric on both
sides (NURL→Claude with tool-use AND Claude→NURL via stdio OR HTTP).
Next up: Phase 5 (thread-per-connection concurrency, the last big
gap before "production-grade" can ship), or Phase 7/8 conveniences
(serve_static, cookie helpers, graceful shutdown) for the
single-threaded path.*

*Aikaisempi: 2026-05-05 — **Phase 6 (routing + middleware) shipped**
in `stdlib/ext/http_router.nu`. Pure NURL, ~340 lines; no
runtime/compiler additions, build fixed-point preserved. Surface:
`Router` (Vec[Route]), `Params` (re-uses `QueryPair` from
`http_request.nu` so `params_get` mirrors `header_get`'s
`? String`-OWNED-copy convention), `router_new/_free`,
`router_get/_post/_put/_patch/_delete` plus `router_any` for the
`"*"`-method case, `router_handle Router HttpRequest → HttpResponse`
(returns response directly — multi-field structs still can't ride `! T
E` Ok arms; this is fine because dispatch always either finds a route
or 404s, never fails). Pattern matcher is a single byte-level
segment-by-segment walk: `:name` captures one segment, `*name`
captures the tail (incl. embedded `/`s), strict trailing-slash
semantics, no auto-redirects. Middleware as handler-wrapping
combinators rather than a `Vec[Middleware]` registry — `with_log_requests`
(`[req] METHOD path` + status to stderr) and `with_cors_default`
(adds permissive CORS headers, short-circuits OPTIONS preflight to
204). Composition is closure capture: `with_log_requests
(with_cors_default base)` works because closure-in-closure capture
shipped 2026-04-26. Test `compiler/tests/http_router.nu`
(unconditional, gated alongside `http_request_parser` /
`http_response_builder` in `run_tests.{bat,sh}`) — 14 dispatch cases
(static, `:id`, `:owner/:repo`, `*path`, method dispatch, `*`-method,
404 fallback for missing/method-mismatch/trailing-slash/empty-segment),
`params_get` hits + miss, middleware composition (GET round-trip with
CORS + OPTIONS preflight 204). **Strategic milestone:** MCP HTTP/SSE
transport now unblocked — every primitive needed (chunked streaming
from Phase 3.3 + routing from Phase 6) exists. Next up: ship
`mcp_server_run_http` in `stdlib/ext/mcp.nu`, OR start Phase 5
(thread-per-connection) for production-grade concurrency.*

*Aikaisempi: 2026-05-02 — Phase 4 (single-threaded HTTP/1.1 server in
`stdlib/ext/http_server.nu`) shipped — **MVP milestone reached**. The
first end-to-end NURL HTTP server is alive: `tcp_listen` →
`server_new listener handler` → `server_run_once` accepts one
connection, parses the request (with overlap-segment body recovery),
runs the handler, writes the response, closes. `server_run` loops
until clean stop. 4xx/5xx error responses for malformed input.
Cross-cutting: bumped compiler-internal `MAX_LEX 256 → 1024` in
`stdlib/runtime.c` — the transitive `$`-include chain overflowed the
old pool. Surfaced two new compiler quirks (mutable-enum-binding
miscompile, multi-`^`-return-in-`??`-arm phi-without-terminator);
worked around in-place, no language-arch follow-ups added (both
fold into the existing multi-field-Ok/Some gap entry). Test:
`http_server_seq.nu` (gated `NURL_NET_TESTS=1`) — curl-spawned POST
round-trips end-to-end, ASan-clean. Build fixed-point holds. Next up:
Phase 5 — concurrency (thread-per-connection) + closure-field-extract
`#`-cast.

---

*Phase 3 entry (kept for archive): Phase 3 (HTTP/1.1 response writer in
`stdlib/ext/http_response.nu`) shipped. Pure-NURL builder: HttpResponse
struct (status + headers + body), header / body / JSON setters,
auto-Content-Length serialisation, 35-entry status_reason table per
RFC 7231, chunked-streaming primitives over TcpConn for SSE
(`response_begin_chunked` / `_write_chunk` / `_end_chunked`). Five
convenience helpers (`response_text/_json/_redirect/_status_only
/_error`). Test: `http_response_builder.nu` (unconditional, ASan-clean,
golden-byte-sequence baseline). No new compiler gaps surfaced. Build
fixed-point holds. Next up: Phase 4 — single-threaded server skeleton
(`stdlib/ext/http_server.nu`) + first end-to-end loopback test.

---

*Phase 2 entry (kept for archive): Phase 2 (HTTP/1.1 request parser in
`stdlib/ext/http_request.nu`) shipped. Pure-NURL parser: request line
+ headers (with RFC 7230 §3.2.2 folding + case-insensitive lookup +
8 KB / 100-header limits) over a `( Vec u )` byte buffer; URL splitter
(`UrlSplit`); query-string parser (`QueryPair`-Vec, percent-decoded);
RFC 3986 percent codec; Content-Length and Transfer-Encoding: chunked
body readers off a TcpConn with configurable size cap. Acceptance:
`http_request_parser.nu` (unconditional, ASan-clean), exercising
well-formed/multi-header/folding/percent-encoded/unsupported-version/
incomplete/malformed/oversized. Bootstrap fixed-point holds.

Three NURL language gaps surfaced and recorded as cross-cutting
follow-ups (none blocking — Phase 2 worked around each cleanly):

  1. `parse_type_paren` doesn't recurse for compound type-args
     (`( Vec ( Pair K V ) )`); workaround is named structs
     (`UrlSplit`, `QueryPair`, `ParsedHeaders`).
  2. `! T E` Ok arms can only carry i64-fitting values; multi-field
     structs miscompile. Workaround is the tagged-struct pattern used
     by `ParsedHead { head, consumed, ok, err }`.
  3. `# StructName 0` default-construction is wrong for multi-field
     structs, breaking `vec_get [MultiFieldStruct]`. Workaround is
     direct `*Header`/`*QueryPair`-pointer iteration via `vec_data`.

Next up: Phase 3 — HTTP/1.1 response writer in
`stdlib/ext/http_response.nu`.*

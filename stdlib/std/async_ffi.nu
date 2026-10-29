// stdlib/std/async_ffi.nu — Async runtime FFI bridge.
//
// FFI-only module: declares the `nurl_fiber_*` / `nurl_runtime_*`
// C symbols implemented in `runtime.c §24`. Kept separate from
// `stdlib/std/async.nu` (which adds the NURL wrapper API) so
// foundational modules like `stdlib/std/channel.nu` can pull in the
// fiber primitives WITHOUT also pulling in the wrapper surface —
// preventing both source bloat and duplicate-declare errors at link
// time when two consumers both want the same symbol.
//
// LLVM rejects two `declare`-lines for the same C symbol within a
// translation unit, so every fiber primitive lives here exactly
// once and is reached through `$`-import.

& `c` @ nurl_fiber_spawn in *u fn in *u env → i

& `c` @ nurl_fiber_spawn_owned in *u fn in *u env → i

& `c` @ nurl_fiber_spawn_joinable in *u fn in *u env → i

unsafe & `c` @ nurl_fiber_join i fiber → v

unsafe & `c` @ nurl_fiber_detach i fiber → v

& `c` @ nurl_fiber_yield → v

& `c` @ nurl_fiber_current → i

& `c` @ nurl_fiber_worker_id → i

unsafe & `c` @ nurl_fiber_park_with_mutex i mutex_h → v

unsafe & `c` @ nurl_fiber_unpark i fiber_h → v

// A park with a deadline that a waker can race safely (runtime_ffi.c
// §25): the fiber parks on a mutex its caller holds, released after the
// swap-out, until nurl_fiber_wake or `timeout_ms` (< 0 = none) — 1
// woken, 0 timed out, -1 not on a fiber (the mutex is still held).
// nurl_fiber_wake answers 1 when it woke the fiber, 0 when the deadline
// claimed it first. A waiter woken either way relocks and re-checks.
unsafe & `c` @ nurl_fiber_park_with_mutex_ms i mutex_h i timeout_ms → i

unsafe & `c` @ nurl_fiber_wake i fiber_h → i

& `c` @ nurl_runtime_init i workers → v

& `c` @ nurl_runtime_worker_count → i

& `c` @ nurl_runtime_run → v

& `c` @ nurl_runtime_shutdown → v

// Phase 5: I/O reactor + timer wheel.
//   *_wait_read/write return 1 on ready, 0 on timeout, -1 on bad ctx.
//   sleep_ms always returns 0.
& `c` @ nurl_reactor_wait_read i fd i timeout_ms → i

& `c` @ nurl_reactor_wait_accept i fd i timeout_ms → i

& `c` @ nurl_reactor_wait_write i fd i timeout_ms → i

& `c` @ nurl_fiber_sleep_ms i ms → i

// TCP-handle helpers the fiber I/O paths need alongside the reactor.
// Declared HERE (not in std/net.nu) so the pure TLS stack — which
// net.nu imports, ruling out the reverse import — can park on the
// reactor without a declaration cycle. `handle` is the runtime-side
// NurlTcp pointer every nurl_tcp_* builtin traffics in, not an OS fd;
// `nurl_tcp_get_fd` is the bridge to the reactor's fd-based API.

unsafe & `c` @ nurl_tcp_get_fd i handle → i

// What a read/write on this socket should wait for, in milliseconds;
// 0 = for ever. The fiber paths need it because they park on the
// reactor instead of on SO_RCVTIMEO.
unsafe & `c` @ nurl_tcp_timeout_ms i handle → i

unsafe & `c` @ nurl_tcp_set_nonblock i handle i on → v

// Absolute write budget shared by native syscalls, TLS records and fibers.
unsafe & `c` @ nurl_tcp_set_write_deadline i handle i ns → v

unsafe & `c` @ nurl_tcp_write_deadline i handle → i

unsafe & `c` @ nurl_tcp_write_wait_ms i handle → i

// Wait for either readable(1) or writable(2) readiness on one fd.
& `c` @ nurl_reactor_wait_io i fd i events i timeout_ms → i

unsafe & `c` @ nurl_tcp_write_nowait i handle *u bytes i length → i

unsafe & `c` @ nurl_tcp_wait_io i handle i events i timeout_ms → i

unsafe & `c` @ nurl_tcp_read_nowait i handle *u bytes i length → i

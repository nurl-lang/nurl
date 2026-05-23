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

& `c` @ nurl_fiber_spawn *u fn *u env → i
& `c` @ nurl_fiber_spawn_joinable *u fn *u env → i
& `c` @ nurl_fiber_join i fiber → v
& `c` @ nurl_fiber_yield → v
& `c` @ nurl_fiber_current → i
& `c` @ nurl_fiber_worker_id → i
& `c` @ nurl_fiber_park_with_mutex i mutex_h → v
& `c` @ nurl_fiber_unpark i fiber_h → v
& `c` @ nurl_runtime_init i workers → v
& `c` @ nurl_runtime_run → v
& `c` @ nurl_runtime_shutdown → v

// Phase 5: I/O reactor + timer wheel.
//   *_wait_read/write return 1 on ready, 0 on timeout, -1 on bad ctx.
//   sleep_ms always returns 0.
& `c` @ nurl_reactor_wait_read i fd i timeout_ms → i
& `c` @ nurl_reactor_wait_write i fd i timeout_ms → i
& `c` @ nurl_fiber_sleep_ms i ms → i

### Fixed

- **A `: ~` copy of a handle that is stored takes its owner with it** (Agora #824). The generated code gives the store the owner's own value. The borrow checker did not know this and kept the owner as the owner. Before this fix, these were accepted and freed or moved one buffer under two names (heap-use-after-free):
  - after `: ~ cur t` and `@ H { cur 0 }`, moving `t` again (`@ K { t }`, `( vec_push d t )`);
  - growing `. q items` while a `~` loop or a slice over `t` was live.

  `t` is now moved into the store, as with `@ H { t 0 }`.
- **A parameter's cursor stored into a local struct is copied** (Agora #824). Take `: ~ cur v` of a parameter, then `@ H { cur 0 }`, `= . q items cur` or `@ ?( Vec i ) { T cur }` in a value the function drops. The struct took the caller's buffer and freed it at return. It is now copied, as `@ H { v 0 }` is. This happens only where the cursor is the parameter's. When it is re-pointed at a local, the store still takes the local's value. A literal the function hands back, or one nested in it, still lends the parameter back, as before. A parameter's cursor stored into an `inout` parameter's field, `= . dst items cur`, keeps the parameter, as `= . dst items v` does.
- **A join's cursor stored into a literal no longer leaks** (Agora #824). `: ~ cur ? k a b` then `@ H { cur 0 }` copies, and `a` and `b` keep their values. Before, the copied one was never released. The same fix stops a leak of the `WsClient` wrapper in `mqtt_connect_ws_cfg` (stdlib/ext/mqtt.nu).
- **A `~` loop over an Rc's payload ends when another handle grows it** (Agora #761). `: ( Vec u ) pv ( rc_get r2 )` with `~ x pv { ( vec_reserve ( rc_get r ) 4096 ) … }`, where `r` is a clone of `r2`, read the moved buffer. The same holds for a helper handed `r`, and for two parameters that are one Rc value. That loop is now refused, as a slice of `pv` already was.

### Changed

- **Reading the owner after its cursor was stored is refused** (Agora #824): `: ~ cur t  @ H { cur 0 }`, then reading `t`. The message names the cursor. Read the value through the store (`. q items`), or store a copy, `@ H { ( mem_dup cur ) 0 }`.
  `stdlib/ext/resolver.nu` reads a frame's node before pushing the frame back onto the solver's stack, for this reason.

### Known issues

- **Some cursors still give their owner's value away unseen** (Agora #840): a cursor of a `??` payload stored inside its arm, and a struct cursor given a field before it is stored. A join's cursor handed to a keeping call still leaks the value it copied, and so does a parameter's cursor re-pointed at a local, in a literal handed back, on the runs it holds the local's value.

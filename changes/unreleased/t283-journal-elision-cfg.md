### Performance

- **A value held only across calls that cannot panic is no longer
  registered with the panic journal** (Agora #283). Inside a `recover`
  extent the compiler drops a binding's journal registration when no panic
  can meet it. It used to keep the registration whenever a call that may
  panic stood anywhere between the binding's start and the end of the
  function, so a handler's per-row value stayed registered because a
  bounds-checked read came lines later. It now follows the function's
  branches from the registration to the binding's end. The decision is per
  slot, all or nothing, so no forget another registration needs is ever
  removed. The journal's semantics are unchanged.
  - `stdlib/ext/json.nu`: the string scans find the first byte that needs
    attention without a mask built by a computed shift. That shift's range
    check made every JSON parse and write count as "may panic".
  - `stdlib/ext/json.nu`: the JsonWriter reads its state through `vec_get`.
  - `stdlib/ext/json.nu` and `stdlib/std/bytes.nu`: appends of existing
    bytes reserve through the unchecked growth.
  - bench/http_server.nu `/async-db?limit=50`: the journal's share falls
    from 8.4 k to 5.7 k instructions per request. A handler-shaped
    microbenchmark spends 5 % fewer cycles.

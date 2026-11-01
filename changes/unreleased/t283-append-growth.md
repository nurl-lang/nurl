### Performance

- **A push or an append no longer makes its callers register with the panic
  journal** (Agora #283). Inside a `recover` extent (every HttpApp handler)
  the compiler drops the journal registration of every binding that no
  panic can reach. But every buffer growth went through `alloc_size`'s
  overflow panic, so nearly every function that pushes or appends counted
  as "may panic", and so did its callers. A growth whose count is a length
  plus elements that already exist in memory (a push, an insert, an
  extend, a string append, a copy, a concatenation) cannot overflow, so it
  now takes an unchecked path with no panic: `__vec_grow_to`,
  `_vec_reserve_more`, `_vec_with_room` and `_string_with_room`. A count a
  caller chose (`vec_with_cap`, `vec_reserve`, `vec_resize_zeroed`,
  `string_with_cap`, `string_repeat`, `vec_map`'s output) still panics on
  overflow, as before.
  - bench/http_server.nu `/async-db?limit=50`: 3.5 % fewer instructions per
    request; the journal's own share halves (16.6 k → 8.4 k instructions per
    request under callgrind).
  - A handler-shaped microbenchmark (recover; 50 rows of jsonb tags parsed,
    built and stringified): 17.3 % fewer instructions, about 21 % fewer
    cycles.
  - No panic, drop or journal semantics change.

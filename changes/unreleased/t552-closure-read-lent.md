### Performance

- **A closure read out of a Vec is lent, not copied** (Agora #552).
  `( vec_at [( @ u64 u64 )] fs i )` used to clone the closure's environment
  on every read, and the caller freed the clone after the call: one
  allocation and one free per call, and a deep copy of whatever the closure
  captured. Bound by name from `vec_at` / `vec_get`-style reads of a Vec
  the function owns by name, in safe code, the read now hands back the
  element itself, as a String's `vec_at` does, as long as the binding is
  only ever called directly. Read any other way (a parameter's Vec, an Rc
  payload, an `unsafe` function), or a binding that is also passed on,
  rebound, captured, or called right after another call in the same
  statement, it is still copied. `bench/captured_closure_queue` goes from 178 ms to 72 ms
  (Rust 78 ms, C 85 ms) and from 14.05M allocations to 109k.

### Changed

- **A closure bound from `vec_at` of a local Vec borrows that Vec**
  (Agora #552), as docs/spec.md §8.4 says. Calling it after the Vec is cleared, freed or
  given a new element (`vec_put` / `vec_set`, at any slot, as for a String read out of it) is now a compile error. (Growing the Vec
  is fine: the closure's environment does not move.) To keep it
  past such a change, bind a copy that owns its environment:
  `( mem_dup ( vec_at … ) )`. Returning such a closure, storing it into an
  owner or handing it to a `sink` parameter still copies it.

### Changed

- **Breaking: a literal handed back lends an `in` parameter it names whole** (AGORA-995, D4c of AGORA-946). `^ @ K { p }`, `^ @ E { V p }`, `^ @ ?K { T @ K { p } }` and `^ @ KK { @ K { p } }` now lend the caller's argument, as `^ p` always did. The caller keeps its argument, and the result borrows it. Before, the literal took the argument over (an inferred `keeps`), so reading the argument after the call was refused ("its value was moved into an owner"). A literal that also holds a value of its own beside the parameter, such as `^ @ P { p ( vec_new ) }`, still takes the parameter over, because a struct is dropped whole.
  - **Migration:** a constructor that is meant to take its argument over says so with `sink`. Code that let the result outlive the argument is now refused with "'k' borrows from 's'".
  - `pair_new` now takes `sink A first sink B second`.
  - A literal of several parameters named whole, of which the function takes one over on another path, takes them all over, as before this change.
  - `json_arr` and `json_obj` now take a `sink ( Vec Json )`.
  - `image_of` now takes a `sink ( Vec u ) data`.
  - toml's internal `__valresult_ok` and `__keyresult_ok`, and nurldb's `__tok`, take their value as `sink`.
  - The hole probes and compiler tests that tested the take-over (h205, h207, agora #160 and #362) now write `sink`.

### Performance

- **A local handed back whole through a lending call is handed over, not copied** (AGORA-995). This covers `^ ( id s )`, `^ ( wrap s )` with `wrap` returning `@ K { p 0 }`, and `: K k ( wrap s ) … ^ k`, where `s` is a local of the function. `s`'s value becomes the result, with no copy and no release. Before, the String or struct was copied and the local released.
  - A value of a type with no copy (a `% Drop` struct) handed back this way is now accepted. Before, it was refused (agora #187).
  - So is an option of a Vec of `% Drop` values a call answers per call for (AGORA-999), such as `^ ( maybe o k )` with `maybe` handing `o` back on one path: `o` is handed over on that path. Before, it was refused (agora #459).
  - A temporary handed to a literal that lends its parameter whole, as in `( wrap ( string_from … ) )`, is the result's, and nothing is copied.
  - Over the tree sweep's changed functions, 83 copy calls and 320 drop calls are gone. Most of them are `HttpStreamState` copies in `http_stream_open_to` / `http_stream_open_bytes_to`.
- **The compiler asks what a callee lends without building anything when it lends nothing** (AGORA-995). Instruction counts against main's compiler at this change's base, built the same way, with peak RSS unchanged:
  - self-compile: −0.43 %;
  - `compiler/tests/anthropic_basic.nu`: −0.21 %.

### Fixed

- **A function forwarding a call that hands back its argument wrapped no longer leaks** (AGORA-995). Example: `^ ( wrapo ( string_from … ) k )` with `wrapo` returning `@ ?String { T p }`. The function's scalar parameter `k`, passed on, counted as a lend, so the caller took the result for a borrow and never released it (LeakSanitizer on main 4b154b9d). A scalar parameter of safe code is no lend now, where the result is no view or pointer.

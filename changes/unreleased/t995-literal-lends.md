### Changed

- **Breaking: a literal handed back lends an `in` parameter it names whole** (AGORA-995, D4c of AGORA-946). `^ @ K { p }`, `^ @ E { V p }`, `^ @ ?K { T @ K { p } }` and `^ @ KK { @ K { p } }` now lend the caller's argument, as `^ p` always did. The caller keeps its argument, and the result borrows it. Before, the literal took the argument over (an inferred `keeps`), so reading the argument after the call was refused ("its value was moved into an owner"). A literal that also holds a value of its own beside the parameter, such as `^ @ P { p ( vec_new ) }`, still takes the parameter over, because a struct is dropped whole.
  - **Migration:** a constructor that is meant to take its argument over says so with `sink`. Code that let the result outlive the argument is now refused with "'k' borrows from 's'".
  - `pair_new` is now `@ pair_new [A B] sink A first sink B second`.
  - The hole probes and compiler tests that tested the take-over (h205, h207, agora #160 and #362) now write `sink`.

### Performance

- **A local handed back whole through a lending call is handed over, not copied** (AGORA-995). This covers `^ ( id s )`, `^ ( wrap s )` with `wrap` returning `@ K { p 0 }`, and `: K k ( wrap s ) … ^ k`, where `s` is a local of the function. `s`'s value becomes the result, with no copy and no release. Before, the String or struct was copied and the local released.
  - A value of a type with no copy (a `% Drop` struct) handed back this way is now accepted. Before, it was refused (agora #187).
  - A temporary handed to a literal that lends its parameter whole, as in `( wrap ( string_from … ) )`, is the result's, and nothing is copied.

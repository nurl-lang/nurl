### Added

- **The drop validator checks what conservation alone cannot see**
  (formal phase D0c, Agora #990). `tools/ncore/tv.sh` now hands
  `tvdrops.py` the core IR's per-function summaries. On every path it
  reports these:
  - a value a callee's `sink` parameter took that the frame releases too;
  - a parameter the function only borrows that it releases;
  - a slot read after its value was released, which is what an early
    release looks like.

  `tools/ncore/tv/selftest.sh` catches each of these, and plain
  conservation accepts two of them.

### Changed

- **More functions validate.** A per-call ownership answer whose key is a
  constant of the module (`__nurl_clear_if` and `__nurl_cloneifk` on
  `@.__nurl_sink.N`) is now followed instead of being reported as
  unsupported. A slot that only holds a borrowed parameter is recognised as
  owning nothing.
  - On the 1986-program corpus, 98236 functions now validate (83518
    before) and 8010 are unsupported (22728 before).
  - There are 0 mismatches.
- **The drop validator claims less where it followed less.**
  - A loop whose drop state still changes after two rounds is reported
    unsupported. It used to count as validated.
  - A `__dropif` releases what its slot holds at the call.
  - A return of a value that was released, handed on, or only borrowed is
    a mismatch.

### Fixed

- **The drop validator no longer accepts six codegen mistakes it used to
  miss** (#2242 review). Each one is now a mutation in
  `tools/ncore/tv/selftest.sh`:
  - A value moved from one slot to another by a load and a store is the
    same value in both slots, so releasing it from each is a mismatch. It
    used to count as a new value.
  - A call to a function with `sink` / `keeps` parameters has every
    argument read, constants included. A call it cannot read is reported
    unsupported. A constant argument used to make it skip the call's checks.
  - A `__nurl_cloneifk` result that the path knows is the value itself, not
    a clone, is checked as that value when it is handed to a `sink`.
  - An unconditional release (`__dropif(true, …)`) gets the same
    borrowed-parameter and `sink` checks as a release under a flag.
  - With `--journal`, a registration must name its slot's own drop flag,
    which is the flag the drain asks. An indirect call counts as a call
    that may panic.
- **`tools/ncore/tv.sh` stops when a step fails.** If `nurlc --emit-core`,
  `nurlc --g` or `tvir.py` fails, it exits nonzero instead of validating
  with an empty file. It also forwards its arguments without word
  splitting.
- **`selftest.sh`'s positive controls require the function under test to
  validate.** A module with no mismatch used to pass even when that
  function was unsupported.

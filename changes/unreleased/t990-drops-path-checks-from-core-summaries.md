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

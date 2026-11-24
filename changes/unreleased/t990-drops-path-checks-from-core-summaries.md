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
- **The drop validator no longer accepts five more codegen mistakes**
  (#2242 review, second round). Each one is a mutation in
  `tools/ncore/tv/selftest.sh`, accepted before and caught now:
  - A clone the path knows was made (`__nurl_cloneif(true, …)`, or a
    `__nurl_cloneifk` whose key and flag are both set) is a value of its
    own. Handing it to two `sink` parameters is a mismatch. It used to
    have no identity, so both handovers were skipped.
  - A parameter of an owning type has its own identity from the entry. A
    borrowed one handed to a `sink` as it came (`eat(%p)`) is a mismatch.
    So is the same in a function with no drop flag of its own.
  - With `--journal`, a registration left enabled after a `sink` parameter
    took the slot's value is a mismatch: a panic there would release what
    the callee owns.
  - With `--journal`, two enabled registrations of one value (two slots
    holding it after `= d s`) are a mismatch: the drain would release it
    twice.
  - A flag cleared while its slot owns a value, with the value handed
    nowhere on the path, is a leak and a mismatch. This is the `off`
    without a `copy` that `formal/D/Drops.lean`'s `checkA` refuses. A
    value counts as handed on when it goes to a call, a store, an aggregate
    or the `ret`, or when another slot owns it. With `--sums`, a call hands
    a value on only at a `sink` / `keeps` position. The case is reported
    unsupported, not validated, in three situations: the value may be a
    clone, it is used where its hand-on is not read (`extractvalue`,
    `phi`), or it came from somewhere not followed. That last covers a load
    through another value's pointer or a field, which may be a lend. It
    also covers a function whose core IR calls `mem_forget`, which gives a
    value up on purpose.
  - On the 1983 programs the corpus compiles, 124 functions move from
    validated to unsupported, and none the other way. The default run
    gives 98164 validated, 7778 unsupported, 0 mismatches. `--journal`
    gives 97830 / 8112 / 0, with 480 journal-checked.
- **The drop validator no longer accepts nine more codegen mistakes**
  (#2242 review, third round). Each one is a mutation of real nurlc output
  in `tools/ncore/tv/selftest.sh`, accepted before and refused now:
  - Two paths that meet in one state except for a value one of them still
    owes a hand-on are no longer merged. The owed value used to be left out
    of the state when no slot or register held it, so the leaking path was
    skipped.
  - A slot the journal alone tracks, or one that is always released, is no
    longer an owner of a value whose flag is cleared. The value stays owed
    until it is released or handed on. A journal `forget` hands nothing
    on.
  - A store into one of the frame's own slots is not a hand-on. The value
    is owned again only once that slot's flag is set.
  - A value moved into an aggregate (`insertvalue`) passes what it owes on
    to the aggregate. The aggregate must then be stored, passed, returned
    or released. A thrown-away aggregate is a leak.
  - A known clone is the frame's to hand on or release. A clone made and
    thrown away is a leak. Functions with no drop flag that make clones are
    checked now too.
  - A parameter stored into a slot that only holds it, then loaded back,
    keeps its identity. Handing that load to a `sink` is a mismatch. A
    `keeps` parameter of a type that owns nothing (a view such as `i8*`) is
    still given no identity.
  - With `--journal`, at a call that may panic, every value still owed a
    hand-on must be held by an enabled registration, either of the value or
    of an aggregate it went into. Otherwise a panic there leaks it.
  - Reported unsupported instead of validated: a value handed on through a
    `__nurl_cloneif` whose condition is not known, before its flag is
    cleared. If the result was a clone, the value itself leaks.
  - Reported unsupported instead of validated: a drop flag copied
    (`store i1 %f`) into a slot that does not hold the source's value. The
    target used to be given the source's identity without holding it.
  - Also: a release of a value a register holds (`__dropifv_T(i1 true, T
    %r)`) now counts as a release. A `store` is read with bracketed types
    (`{ i1, %T }`).
  - Registers that no path reads again are left out of the state, so paths
    that loaded different registers on the way still meet. This alone moves
    38 functions from unsupported (a loop whose state still changed) to
    validated. It is a sound reduction: no check depends on a dead register.
  - On the 1983-program corpus, the default run goes from 98164 validated,
    7778 unsupported, 0 mismatches to 98197 / 7745 / 0. `--journal` goes
    from 97830 / 8112 / 0 to 97863 / 8079 / 0, with 480 journal-checked
    both times. Five functions move from validated to unsupported. Three
    read a field (`extractvalue`) of a value still owed, and two are
    clone-only functions whose loop is not followed.
- **`tools/ncore/tv.sh` stops when a step fails.** If `nurlc --emit-core`,
  `nurlc --g` or `tvir.py` fails, it exits nonzero instead of validating
  with an empty file. It also forwards its arguments without word
  splitting.
- **`selftest.sh`'s positive controls require the function under test to
  validate.** A module with no mismatch used to pass even when that
  function was unsupported.

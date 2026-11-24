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
- **The drop validator no longer accepts eight more codegen mistakes**
  (#2242 review, fourth round). Where a construct is rare, it is now
  reported unsupported rather than modelled. Each one is a mutation of real
  nurlc output in `tools/ncore/tv/selftest.sh`, accepted before and refused
  now:
  - A function whose only ownership operation is a release by value
    (`__dropifv_T`) is checked. Only a function with no drop flag, release,
    clone, journal entry or `sink` call is skipped.
  - Two paths whose aggregates carry different values are no longer merged
    at a join. The state key now holds what every aggregate carries, not
    only what the ones still owed carry.
  - A store of an owned value is a hand-on only through a pointer to memory
    that is not the frame's. That means a parameter (the output or an
    `inout` one), a pointer read through one or kept in a slot that holds
    only such pointers, a field of a parameter's aggregate, or a pointer a
    call returned that was handed none of the frame's own storage. A store
    into the frame's own storage, a field of a slot included, or through a
    pointer that is not followed, is reported unsupported.
  - A field replaced (`insertvalue`) in an aggregate where it held a value
    the frame owned is reported unsupported. The result used to share the
    base's identity, so the replaced value's obligation went with it.
  - One value moved into an aggregate twice (into two fields, or into two
    aggregates) is a mismatch: both would release it. Distinct clones moved
    into two fields still validate.
  - (`--journal`) At a call that may panic, an aggregate still owed a
    hand-on is held only by a registration of itself. One held by a
    registration of a single value it carries is reported unsupported: the
    other values it carries are not all followed.
  - A release by value under a flag whose value is not known is reported
    unsupported for any value the frame follows, not only one still owed.
    It used to pass for a value a `sink` had taken. A flag known false is
    still no release.
  - A release by value of a possible clone (a `__nurl_cloneif` whose
    condition is not known) is reported unsupported. It used to count as
    the release of the value itself. A release of the value itself, known
    to be no clone, still counts.
  - On the 1983-program corpus, the default run goes from 98197 validated,
    7745 unsupported, 0 mismatches to 98185 / 7757 / 0. `--journal` goes
    from 97863 / 8079 / 0 to 97852 / 8090 / 0, with 480 journal-checked
    before and 479 now. Of the 12 functions that move to unsupported in the
    default run, five store an owned value into the frame's own storage,
    a result temporary or a field of a slot. Three store through a pointer
    cast from an integer (`inttoptr`, the btree's raw node blocks). Four
    release by value an aggregate under a run-time answer (`__nurl_ret_own`).
    `--journal` loses the same kinds, less two of the btree functions that
    were unsupported there already, plus one aggregate held at a panic by
    a registration of the value it carries.
- **The drop validator checks slots of literal aggregate types.** A slot
  such as `alloca { i1, %String }` (an option, a slice, a result
  temporary) used to be taken for another frame's, because the type has
  commas, so its releases were skipped and the function could validate
  unchecked. LLVM types are now read by a tokenizer that balances `{}`,
  `[]`, `<>` and `()`, in allocas, loads, stores, releases, clones and
  parameter lists. Such a slot owns where its type is one a `__dropif_T`
  loads or a `__dropifv_T` takes. A line of those kinds whose types do not
  parse, or a parameter list not read whole, is reported unsupported.
  - `selftest.sh` gains three mutations on a new program with an option
    slot: a leak, a double release, and a release after a `sink` took the
    value. The validator before this change accepted all three. Each is a
    mismatch now.
  - A slot that only ever holds what was loaded from a slot holding a
    borrowed parameter is borrowed too, so it owns nothing. That covers the
    result temporary of a function that lends a parameter back.
  - On the 1983-program corpus, the default run goes from 98185 validated,
    7757 unsupported, 0 mismatches to 98065 / 7877 / 0. `--journal` goes
    from 97852 / 8090 / 0 to 97733 / 8209 / 0, with 479 journal-checked
    before and 481 now. 193 functions move to unsupported and 73 to
    validated. Of those moving to unsupported, 116 have a slot of an
    owning aggregate type with no drop flag. These are mostly result
    temporaries (options, `recover`'s result) and 44 slices
    `{ T*, i64 }`, whose LLVM type is the same as an owned slice's. The
    other 77 have an option slot's flag set from a run-time answer
    (`__nurl_ret_own`, 76 of them). The 73 now validated have their option
    slots checked: they were unsupported before because a release of a slot
    the validator did not take for the frame's was read as a flag it could
    not follow.
- **`tools/ncore/tv.sh` stops when a step fails.** If `nurlc --emit-core`,
  `nurlc --g` or `tvir.py` fails, it exits nonzero instead of validating
  with an empty file. It also forwards its arguments without word
  splitting.
- **`selftest.sh`'s positive controls require the function under test to
  validate.** A module with no mismatch used to pass even when that
  function was unsupported.
- Two follow-ups from the same round. An `insertvalue` result's chain of
  fields is resolved from the definitions, not read in the order the blocks
  are listed, so replacing a field that holds an owned value is refused
  wherever LLVM lists the blocks. A field set on an aggregate that carries
  owned values without an `insertvalue` here building it (a phi of
  literals) is unsupported. And a pointer a call returns counts as outside
  the frame only when every argument is a scalar, a constant or traced
  outside the frame: one traced nowhere may hand the frame's own storage
  back. The corpus totals are unchanged.
- Fifth round: an aggregate handed to a `sink` takes what it carries, so a
  release of one of those afterwards is a mismatch; an `alloca` with a count
  other than one, or an address space, is unsupported (it was read as a slot
  that owns nothing); `volatile` and `atomic` flag stores set the flag as a
  plain store does; and types compare without their whitespace. New
  selftest program `literal_of_clones_handed_to_a_sink.nu`. The corpus
  totals are unchanged.
- A pointer read out of a global is what was stored there, not the global:
  it counts as outside the frame only when every store into that global in
  the function is.
- An integer handed to a call may be one of the frame's own pointers turned
  into one (`ptrtoint`): where the frame does that to a pointer not traced
  outside, the pointer such a call returns is not taken for outside storage.
  11 corpus functions move from validated to unsupported (98054 / 7888 / 0).
- The same holds for a floating-point argument (a pointer's bits bitcast to
  a float), and the question of what a frame turns into integers no longer
  asks itself into a recursion: asked again while it is answered, it is
  unsupported.
- An aggregate handed to a `sink` is checked member by member first: one
  already released or handed on is a mismatch.

### Fixed

- **An enum with a `% Drop` of its own runs its destructor and then drops
  its payloads, wherever it lives** (Agora #641). As a binding its impl
  ran and the payloads were never dropped (a leak); as a `Vec` element, a
  struct field or a temporary a `??` matched, the impl never ran at all.
  It is dropped as a struct with a `% Drop` is now: the impl, then the
  payloads of the variant that is there, once each, also when the impl or
  a payload's destructor panics under `recover`. The enum stays whole for
  its destructor: a `??` arm is lent its payloads.
- **A payload handed back out of an enum the function keeps is the
  caller's own copy** (Agora #641). `?? . w en { V x s → { ^ s } }` over a
  local struct `w` handed the caller the very `String` that `w`'s drop
  then freed: a heap-use-after-free in safe code, with no panic involved;
  a boxed payload's field was copied but the copy leaked. The caller now
  gets a copy it owns (by name, as a join's value, as a field of a boxed
  payload), for an enum in a local's field and for an enum with a
  `% Drop` of its own alike. A payload that cannot be copied (a `% Drop`
  value) is refused there: "this hands back a payload of an enum this
  function keeps and releases, payloads and all, on the way out".
- **A payload handed back out of an enum bound from a call moves out of
  it** (Agora #641). `: E e ( mk ) ?? e { V x s → { ^ s } }`, with `E`
  holding a `% Drop` value somewhere, handed the caller the `String` that
  `e`'s drop then freed (heap-use-after-free), and `^ x` a `% Drop` value
  that both dropped. The payload is taken out of the enum now, as it
  always was for an enum bound from a literal: no copy, and the enum drops
  the rest. The fourth and later payloads of a variant, handed back out
  of a parameter's enum, are lent back as the first three are (the caller
  and the enum dropped them twice).

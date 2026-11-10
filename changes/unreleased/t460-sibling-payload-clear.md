### Fixed

- **Two payload bindings of one enum value are one storage** (Agora #460).
  `?? e { Some xs → { : String s0 ( vec_at [String] xs 0 ) ?? e { Some ys
  → { ( vec_clear [String] ys ) } … } … s0 } }` read the element the inner
  arm cleared: a heap-use-after-free. A call that may drop what an
  in-place `??` payload holds now ends the borrows taken from the owner's
  other payloads too, with a message that names the payload that was
  passed. The closure form, a `wipe` that matches the captured enum and
  clears its payload, is refused by #424's fix.

### Fixed

- **An element handed back out of a lend of a lend of a local is the
  caller's own** (Agora #553). Three shapes gave the caller an element as
  its own and then the local's drop freed it under the caller
  (heap-use-after-free):
  - `^ e` of a `vec_get` payload of a `vec_get` payload of a local
    `( Vec ( Vec String ) )`;
  - `^ e` of a `slice_at` element or a `slice_get` payload of a slice of a
    local Vec;
  - `^ . p s` of a field of a `vec_get` payload of a local `( Vec P )`.

  The lend chain is now followed to the local. A slice bound from a call
  keeps what it views. The element or field is taken out of its Vec slot
  (no allocation) where the slot is known, and copied otherwise. Handed
  back out of a parameter, it stays a lend. Shapes the fix does not reach (a direct
  `^ ( slice_at … )`, other slice makers, a bound or option payload field,
  closures) are Agora #560. A defer that reads the slot after the `^` took
  the element out is #561.

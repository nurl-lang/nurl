### Fixed

- **A `vec_get` payload taken out of its Vec takes the right element after
  a reorder** (Agora #373). `^ e` out of `( vec_get [String] vs 0 )`
  emptied slot 0 by index. After a `vec_swap`, a `vec_insert` or a
  `vec_reverse` (directly, through a function, or in a closure), slot 0
  held another element: that one leaked, and the Vec still dropped the one
  handed back (heap use after free). The take now finds the slot by the
  value's own bytes (`nurl_vec_slot_take_if`): slot 0 first, the slot it
  moved to otherwise. No program is newly refused.

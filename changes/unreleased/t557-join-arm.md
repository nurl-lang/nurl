### Fixed

- **A borrow taken through a `??` whose arm is a ternary of payload fields ends when a later `??` changes that payload** (AGORA-557, the join-arm shape). `: k ?? ev { A p → ? == c 1 . p a . p b … }` borrowed nothing, so an element of `k` read after `?? ev { A p → { ( vec_clear . p a ) } … }` read freed memory. It is refused now: read the borrow before the second match.

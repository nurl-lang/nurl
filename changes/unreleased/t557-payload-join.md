### Fixed

- **A borrow taken through one `??` ends when another `??` changes the same payload** (AGORA-557, four shapes). With `: k ?? ev { A p → . p a … }` and an element of `k` held, a later `?? ev { A p → { ( vec_clear . p a ) } … }` freed what the element pointed into. The same held through a block arm, through a field viewer `: j . p a`, and for a struct element's field. All are refused now. A second match that only reads is still accepted.

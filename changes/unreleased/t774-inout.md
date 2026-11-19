### Fixed

- **A view a callee writes into an `inout` parameter ends when an Rc payload it may reach is reset through another handle** (AGORA-774, now closed). With `@ view_into ( Vec ( Rc ( Vec u ) ) ) hs inout ( Slice u ) out → v { = out ( slice_from_vec ( rc_get ( vec_at hs 0 ) ) ) }`, the caller's `out` kept reading the payload after another handle cleared and shrank it. That read is refused now.

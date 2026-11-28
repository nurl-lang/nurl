module

public import D.Drops

@[expose] public section

/-! Phase D: code generation preserves the semantics, by translation
validation. D2 (`D/Drops.lean`): what a drop validator's "validated"
means. A path the model checker `D.checkA` accepts (drop flags as
codegen's ownership record: owned = flag set and not released) runs on a
concrete heap with no double free, no use after free and no leak
(`D.validated_safe`). The guarantee is for `checkA`'s verdict over the
modeled operations. `tools/ncore/tvdrops.py` is an executable validator
written to follow `checkA`'s rules; that it decides as `checkA` does is
checked by its self-test and corpus, not proved, so a `validated` from it
carries this theorem only as far as it implements `checkA` faithfully
(github#2242's review).

"No use after free" is about the operations the model has: a `__dropif`
or a handover (`clr`) of a block that is no longer live. The model has no
operation that reads a slot's value, and a `clr` whose flag is clear is a
no-op that leaves the slot naming whatever block it named, released or
not. So a value used, or handed to a callee, after its block was released
is outside what `validated_safe` says. That is D0c's slot-read check in
`tvdrops.py`, tested, not proved. The theorem is about `checkA`'s paths,
not about the generated code as such. -/

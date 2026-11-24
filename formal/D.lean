import D.Drops

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
(github#2242's review). -/

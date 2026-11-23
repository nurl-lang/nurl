import D.Drops

/-! Phase D: code generation preserves the semantics, by translation
validation. D2 (`D/Drops.lean`): what the drop validator's "validated"
means. A path `tools/ncore/tvdrops.py` accepts (drop flags as codegen's
ownership record: owned = flag set and not released) runs on a concrete
heap with no double free, no use after free and no leak
(`D.validated_safe`). -/

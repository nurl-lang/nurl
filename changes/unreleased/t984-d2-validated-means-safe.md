### Added

- **What the drop validator's verdict means, proven** (formal phase D2).
  `formal/D/Drops.lean` models one path through a function the way codegen
  writes it: owned and unowned stores, moves out, `= d s`, flag clears and
  `__dropif`. It proves that a path the validator's check accepts runs on a
  concrete heap of live blocks with no double free, no use after free and
  nothing left live at the return (`D.validated_safe`), on Lean's standard
  axioms only.

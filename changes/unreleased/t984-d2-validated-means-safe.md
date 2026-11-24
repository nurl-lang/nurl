### Added

- **What the drop validator's verdict means, proven** (formal phase D2).
  `formal/D/Drops.lean` models one path through a function the way codegen
  writes it: owned and unowned stores, moves out, `= d s`, flag clears and
  `__dropif`. It proves that a path the validator's check accepts runs on a
  concrete heap of live blocks with no double free, no use after free and
  nothing left live at the return (`D.validated_safe`), on Lean's standard
  axioms only. The theorem is about the model checker `D.checkA` over the
  modeled operations; `tools/ncore/tvdrops.py` follows `checkA`'s rules, and
  that it decides as `checkA` does is tested (its self-test and corpus), not
  proved.

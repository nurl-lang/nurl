### Fixed

- **Three holes found closed on main, each guarded by probes now** (Agora #402, #583, #834). A holder of both a slice of a Vec and a view of one of its elements' bytes is ended when that element grows in place. An `inout` holder given a view copied out of an `inout` struct of views (`= w @ W { . src v }`) is tied to what the struct views. A closure literal that grows an element lent out of its own parameter, called on an Arc's payload, is refused by the frozen-payload rule. All three were heap-use-after-frees (the last a data race), and later fixes in the same families closed them. Seven probes guard them now: six refused and one reader that runs clean.

### Changed

- **The list of open soundness holes in `docs/LIMITATIONS.md` is re-checked against main** (2026-11-15 sweep). Every open-hole entry and every open hole task was re-run under ASan. Seventeen entries whose holes are closed are gone, among them #424, #460, #462, #466, #487, #545, #560, #575, #631, #637, #647, #669, #677, #738, #776, #797 and #800. The entries for #242, #479 and #838 now say only what still faults. #638's rest moves under #846, and #656's keep twin becomes #868. Ten open holes that had no entry now have one: #563, #569, #606, #762, #789, #812, #842, #844, #846 and #847. That makes 37 known open. Ten elaborated twins in `open/twins.txt` no longer fault, and `check.sh` runs them again.

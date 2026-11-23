### Fixed

- **A closure over a value whose `% Drop` reaches an `Rc` now counts as a way out at its block's end too** (AGORA-952 follow-up). This covers a function with no borrows. Before, such a release while an `inout` field taken by a `sink` was still empty was accepted, and a `recover`ing caller read a null handle.

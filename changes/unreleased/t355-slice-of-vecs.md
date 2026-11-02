### Fixed

- **A Slice of Vecs compiles** (Agora #355). nurlc gave the data pointer of
  a `( Slice ( Vec u ) )` (or of any Vec type) drop glue as if it were the
  Vec itself, so it emitted `drop__Vec__u8*` and clang rejected the
  program. A pointer owns nothing it points at, and it now gets no drop.

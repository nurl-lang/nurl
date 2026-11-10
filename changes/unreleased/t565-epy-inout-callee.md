### Fixed

- **A `??` arm that replaces its own enum binding through an `inout` callee
  can no longer read the old payload** (Agora #565). `?? o { MSome s → {
  ( reset o ) ( read s ) } }`, with `reset` giving its `inout` parameter
  a new value, read the payload it released (heap use after free). This
  is refused now, as `= o …` in the arm already was (#1678).

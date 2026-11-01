### Fixed

- **A destructor that reads a view is found at any depth** (Agora #340).
  The borrow checker asks whether dropping a value may run a program's
  `% Drop` that reads a view (a view it holds whose source dies first is
  then refused). That walk through the value's fields, elements and
  payloads stopped at depth 8 and answered "no", so a holder nine layers
  down, such as nine nested structs or eight and a Vec, was accepted, and
  its destructor read a freed String (heap-use-after-free). The walk now
  has no depth limit: it keeps the types it has met, so a type that holds
  itself ends the search instead.

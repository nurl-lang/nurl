### Fixed

- **A closure several threads run may clone an Arc field of a struct it
  captured** (Agora #684). `( arc_clone [Pl] . a ap )` inside a closure
  kept in an Arc was refused — "the closure changes 'a' when it runs (it
  hands it to 'arc_clone', which changes it)" — though only the share
  count changes, atomically, and the same clone of an Arc captured
  directly was accepted. The rule now asks what the field path names,
  through fields held by value; a field handed to an `inout` or `sink`
  parameter still changes the capture's storage and stays refused.

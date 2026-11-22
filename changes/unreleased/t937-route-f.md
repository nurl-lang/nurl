### Changed

- **Formal proof: groundwork for calls that change the caller's memory inside a `Vec`'s elements** (AGORA-937). The design now takes route F: a frozen root may be changed strictly inside its elements, as long as the change ends no lent parameter.
  - The memory invariant is proved to survive such a kill, frozen root or not.
  - The conditions a call must meet before its callee may change through a region now speak only of live bindings. A separate condition covers destructors.

  Nothing changes in nurlc.

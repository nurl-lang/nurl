### Fixed

- **A `% Drop` parameter under another name keeps its permissions**
  (Agora #768). `: R q p` over a by-value parameter `p` whose type has its
  own drop now hands `p` over to `q`, as for a local. `( eat q )` is
  accepted where `( eat p )` was, and a later use of `p` is refused as a
  use of a moved value. It was refused with "'q' is a borrow…".

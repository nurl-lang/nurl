### Fixed

- **Two destructors the younger-view check could not see are found**
  (Agora #363). A value whose drop may read a view refuses a view of a
  binding declared after it, which is freed first. The check missed a
  library handle's type argument written with `?` (`( HashMap i ?W )`)
  and a result's error side (`!i W`). Such a holder was given a younger
  view and its destructor read freed memory. These cases are now refused
  like the rest. A handle's own `S_drop` hook that reads a view is still
  open (docs/LIMITATIONS.md).

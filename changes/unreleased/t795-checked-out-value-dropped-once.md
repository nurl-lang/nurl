### Fixed

- **A value checked out of a `Locked` or an `Rc` and never put back is
  dropped once** (Agora #795). `locked_take` / `rc_take` leave zero bytes
  in the slot; when the last share went, its drop ran the value's drop
  glue over them, so a `% Drop` type's destructor ran a second time, on
  zeros (a destructor that writes a field faulted). The last share of a
  `Locked` now asks the lock whether its value is out (`nurl_lk_taken`)
  and then releases only the latch; `Rc_drop` and the runtime's release
  paths (the nested release and the cycle collector) skip a value whose
  `RC_TAKEN` bit is set. The check runs on the last share's drop only.

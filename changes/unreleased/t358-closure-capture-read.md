### Fixed

- **A closure made after a capture's borrow ended is refused where it is
  made** (Agora #358; probes closure_made_*,
  closure_under_recover_reads_*). `: W w` given a view of a block's
  local String, then `\ → v { ( nurl_println . w v ) }` after the block,
  read freed memory when called. The direct read was refused, but the
  closure's reads of its captures were checked only inside its own body.
  Making the closure now reads what it captures, as A2 types a package
  literal. A capture the closure only assigns to is not read.

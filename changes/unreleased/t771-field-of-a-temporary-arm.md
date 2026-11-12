### Fixed

- **A field read out of a `( mem_dup x )` copy, or out of a call's
  temporary as a `?` arm, is released** (Agora #771). `. ( mem_dup o )
  name` left the whole copy to nobody — a builtin has no callee answer for
  the read to take the field over by — and `? c . ( mk ) name …` (bare or
  as a block's tail) took the field the read had taken over for a lend, so
  it leaked. The read of a copy now takes the field and drops the rest of
  the copy, and the join's arm answers by the read's own bit, as a return
  of it already did.

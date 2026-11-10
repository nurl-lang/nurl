### Fixed

- **A borrow ended by one call is no longer readable by another call of
  the same statement** (Agora #577). `( nurl_println_int + ( cz fs ) (
  string_len s ) )`, with `cz` clearing `fs` and `s` a borrow of its
  element, read freed memory; so did `? == 0 ( cz fs ) ( string_len s ) 0`
  and `( two v ( grow line ) )` with `v` a view of `line`. On separate
  statements these were refused; now they are within one. A read that runs
  before the clearing call (`+ ( string_len s ) ( cz fs )`) is unaffected.

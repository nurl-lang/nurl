### Fixed

- **A value lent to a call, ended by a later argument of it** (Agora
  #604): in `( two ( string_data s ) ( cz fs ) )`, `cz` clears `fs`
  before `two` runs, and `two` read freed memory. So did `: s w ? == 0
  ( cz fs ) v `` ` with `v` a view of `fs`'s element. Both are now
  refused, as their forms bound to names first already were. The message
  names the argument and the call that ended what it points into.

### Fixed

- **An option or result given back its own value by a call keeps it**
  (Agora #342). `= o ( id o )`, with `id` returning its argument and `o` a
  `?String` or `!String i`, dropped o's old value and then held it, so the
  next read hit freed memory. The String form already checked whether the
  call handed the same value back, and options and results now do too.
  A call that hands its argument back on some runs only is still open
  (docs/LIMITATIONS.md).

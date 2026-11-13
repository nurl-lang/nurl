### Fixed

- **A value block's tail is its own binding even beside an outer one of
  its name** (Agora #629, #626). `: String e { : String s ( … )  ( eat s )  s }`
  with an outer `s` handed the consumed value on (a use-after-free); it is
  refused now, as without the outer `s`. A block whose tail is its own fresh
  `s`, after the outer `s` was moved, is accepted. `= s { : String s ( … )  s }`
  into an `inout` parameter is handed over too.

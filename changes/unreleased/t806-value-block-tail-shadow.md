### Fixed

- **A value block's tail spelled like the assign target is handed over**
  (Agora #806). In `= s { : String s ( … )  s }` the block-local `s` was
  dropped at the block's end and the freed value was stored into the outer
  `s`: a use-after-free, in a loop, for a String, a Vec or a `% Drop`
  struct. It is now handed over as `= s { : String u ( … )  u }` is. One
  already handed to a sink inside the block is refused.

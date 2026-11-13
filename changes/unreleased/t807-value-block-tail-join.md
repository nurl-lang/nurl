### Fixed

- **A value block whose tail is a join hands over the binding an arm
  selects** (Agora #807, #821, #827). In `= s { : String u ( … )  ? c { u }
  { … } }` the arm lent `u`, which the scope's end then released under `s`:
  a use-after-free in a loop or after a sink, for a String, a Vec or a
  `% Drop` struct, through `?` and `??` and an inner block's tail. A join
  of two block locals (`: P e { : P s … : P t … ? c s t }`) handed to a
  sink freed the struct twice, and pushed into a Vec it leaked both. The
  arm now moves the local into the block's value on its path.

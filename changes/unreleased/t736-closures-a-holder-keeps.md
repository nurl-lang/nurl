### Fixed

- **The closures a struct, an option or a Vec holds do what they do
  wherever the holder goes** (Agora #736, #838, #845). A closure that replaces
  an Rc's payload, stored in a struct's field, an option or a Vec, ran
  unseen:
  - when the holder was handed to a function that runs it;
  - when the closure was read back out and run here;
  - when another closure ran it through the holder.
  A slice of the payload taken through another handle then read freed
  memory. The same held for a join of closures handed to a function that
  runs it, and for a closure a maker hands back stored into a holder,
  or into the holder a builder hands back.
  A maker's closure over an `rc_clone` of its parameter carried nothing
  either (Agora #845): the clone shares the parameter's payload.
  These are refused now: the views end where the holder is handed, as
  they do where a closure is handed. Closures in holders that only read
  the payload, or change an Rc of another type, still compile, and so
  does registering one more tool on a server whose tools share state.

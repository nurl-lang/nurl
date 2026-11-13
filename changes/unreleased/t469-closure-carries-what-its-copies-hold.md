### Fixed

- **A closure carries the views its captured owners hold** (Agora #469,
  #467). A closure that captured a `( Vec s )` holding a view of a String
  was taken to hold nothing of anybody's. These compiled, and the closure
  read freed memory:
  - handed to `thread_spawn` while this side freed the String (also a
    `vec_clone` of a parameter's Vec of views);
  - handed back out of a function over a view of the parameter, then run
    after the caller's String was gone (also through a struct's view
    field, and a struct holding the closure);
  - handed back over a view of the function's own local;
  - stored into an owner that outlives the String.

  Each is refused now. A Vec of Strings it owns, a Vec of literals, an
  `Arc` share, and views of a String that is still alive where the closure
  runs, all still compile.

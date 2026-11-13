### Fixed

- **A closure crosses to a thread by what it captured, not by its
  signature** (Agora #788). A closure that captured nothing but hands back
  a `?( Rc i )` (`\ i k → ?( Rc i ) { ^ @ ?( Rc i ) { T ( rc_new [i] k ) } }`)
  was refused as a thread's capture, in a struct, in a `Vec` of options,
  on a `Channel`, in an `Arc` and as a `[X: Send]` argument, as if it held
  an `Rc`. It now compiles. A closure over an `Rc` is still refused. The
  error now names the `Rc` it captured and the line the closure was built
  on, where before it named the closure's binding.

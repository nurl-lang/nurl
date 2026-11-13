### Fixed

- **A closure's captures follow it into whatever holds it** (Agora #665,
  #717, #718). The thread rules ask what a closure captured where a value
  holding it crosses to another thread, or goes into an Arc. A struct
  holding a closure pushed into a Vec, an optional closure in a Vec, a
  closure field assigned after the struct was built, a Vec a maker fills
  and hands back, and a closure a helper pushes into the caller's Vec all
  carried nothing, so a closure over an `Rc` crossed to a thread, and one
  that gives away its capture ran on eight threads from an Arc. Each of
  these is now refused with the capture named, as the closure stored bare
  already was. A Vec of closures used on one thread, or holding closures
  whose captures are Send, is accepted as before.
  `stdlib/ext/dchannel.nu`'s server store (`DStore`) and its queues (`DQ`)
  now say they synchronise themselves (`% Sync`): they are reached only
  under their mutexes, and the handlers a server runs on its threads
  share them. Without that, the server is refused under the rule above.

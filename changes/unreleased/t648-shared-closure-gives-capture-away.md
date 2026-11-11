### Fixed

- **A closure several threads run can no longer give a value it captured away** (Agora #648). A closure kept in a struct in an `Arc` and run by eight threads, whose body hands its captured struct to a `sink` (or to a function that takes it over, at any depth), compiled, and two threads gave the same `Vec` away: a double free. A closure that gives a capture away can run once, and its environment records that with a plain flag, which two threads read together.

### Changed

- **Keeping a closure where several threads may run it (an `Arc`, a server's handler) is refused when its body gives a capture away** (Agora #648): "the closure built on line N gives 'a' away when it runs …". Give each thread a value of its own (a closure built for each thread, over its own copy), or keep the value outside the shared closure and let the closure read it. A `thread_spawn` body, which one thread runs once, still gives its captures away.

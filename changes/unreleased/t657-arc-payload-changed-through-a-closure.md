### Fixed

- **A closure cannot change an Arc's payload either** (Agora #657). A
  named function called on `( arc_get a )` that changes its argument was
  refused, and so was the change written out in place. Through a closure
  these compiled, and every thread holding a clone changed one value with
  no lock (a double free on every run, with eight threads):
  - a closure value, a copy of one or a closure parameter called on the
    payload;
  - a closure that captured a view of the payload and changes it, run
    here, by a function it is handed to, or by another closure.

  Each is refused now with the frozen-payload message. A closure that
  only reads the payload, or sends on a channel the payload holds, still
  compiles.

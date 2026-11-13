### Fixed

- **An owned slice handed somewhere else moves its buffer there** (Agora #545). These were heap-use-after-free, double frees, or leaks:
  - `: [i q ( mk )  ^ @ Box { q }`, `^ @ Holder { q 1 }`, a literal nested in a returned one, and the same on one path only: q was released at the return while the caller freed the field. The literal now takes the buffer.
  - `= . h v q` into a field h owns: q and the field both freed one buffer. The field takes an owned q, and copies any other slice; the value it replaces is freed. Reading q after the move is refused ("use of moved value 'q'").
  - An `inout [i` parameter given a literal, a call's slice or an owned local leaked the caller's old buffer. It is now released.
  - `= p q` into an `inout [i` parameter, with q a borrowed slice: the caller's slot shared q's buffer (double free). The buffer is now copied.
### Changed

- **A `: ~` copy of a slice is a borrow** (Agora #545). `: ~ [i d a  ( setl d )`, where setl gives its `inout` slice a new value, is refused: "'d' does not own its value: it borrows it from 'a'", as for a String.
- **An `inout` slice of elements that own values cannot be given a slice it does not own** (Agora #545). `= p q` with p an `inout [String` and q a borrowed `[String` is refused; copying the elements one by one is not supported there. Give it a fresh slice, or pass the owner to a `sink` parameter and store that.
- **An enum with a slice payload compiles and releases it** (Agora #841). `: | E { EA [i EB i }` produced invalid IR (its drop read the boxed payload as a slice of no type), and the payload was never freed. The enum's drop now releases the slice, and its elements where they own values. An owned slice binding moved into such a payload moves, so reading it after is refused.

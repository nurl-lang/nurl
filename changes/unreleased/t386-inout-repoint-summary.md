### Fixed

- **A holder an `inout` helper points back is no longer refused as still
  viewing a local** (Agora #386). `( reset w )`, where `reset` makes no call,
  arms no defer, and whose last write to its `inout` parameter is a struct
  literal of literals (`= w @ W { `literal` }`) before any exit, now ends
  what `w` viewed, as `= w …` written in place does. A helper that repoints
  only in an arm, after an early return, makes a call, arms a defer, writes
  the parameter again afterwards, or repoints to anything but literals is
  still taken as leaving the old value. A recursion whose base case
  repoints is not covered yet.

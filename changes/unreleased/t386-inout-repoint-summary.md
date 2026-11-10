### Fixed

- **A holder an `inout` helper points back is no longer refused as still
  viewing a local** (Agora #386). `( reset w )`, where `reset`'s first
  statement gives its `inout` parameter a struct literal of literals
  (`= w @ W { `literal` }`) and it makes no call, arms no defer and writes
  the parameter nowhere after that, now ends what `w` viewed, as `= w …`
  written in place does. A helper that repoints later in its body, only in
  an arm, after a call, to anything but literals, or a call of it that may
  be skipped (`& c ( reset w )`) is still taken as leaving the old value.
  A recursion whose base case repoints is not covered yet.

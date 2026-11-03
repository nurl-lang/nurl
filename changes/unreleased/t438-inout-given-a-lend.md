### Fixed

- **An `inout` String or Vec given a lend of another value copies it**
  (Agora #438; probes inout_*_given_a_*). Inside `@ put inout String o
  String other → v { = o ( id other ) }`, the call's result was stored in
  the caller's binding as it was. The binding then shared `other`'s buffer
  (heap-use-after-free once one of them was released), and its own old
  value leaked. The same happened with `= o ( pick o other 1 )` and `= o (
  id ( id other ) )`. The result is now compared with the old value at run
  time: the old value itself stays as it is, and anything else is copied
  in where it was lent, with the old value released.

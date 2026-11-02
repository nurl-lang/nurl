### Fixed

- **An option owner given a binding of a lend of its own value compiles**
  (Agora #425; probes option_owner_given_a_bound_lend_*). For example,
  `: ?String t ( pick o other k )` then `= o t`. The hand-over of `o`'s
  old value to its borrower `t` keyed the owner by its payload and the
  borrower by its own option type, which has no key. The comparison
  printed an empty operand (`icmp eq i8* , %r…`), which clang rejected.
  Both sides are now keyed by the payload. A missing key is reported as
  nurlc's internal error, not as invalid IR.

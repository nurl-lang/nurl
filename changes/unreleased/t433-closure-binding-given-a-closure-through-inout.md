### Fixed

- **A closure binding a callee reassigns through an `inout` parameter is
  called as the closures the callee may give it** (Agora #433; probes
  closure_binding_given_*). `( setf g clr )` with
  `@ setf inout ( @ v ( Vec String ) ) f … { = f src }` left `g`'s calls
  answered by the reader it was bound to, so a later `( g v )` ended no
  borrow of `v`'s element. It is refused now. A callee assigning a reader
  stays accepted.

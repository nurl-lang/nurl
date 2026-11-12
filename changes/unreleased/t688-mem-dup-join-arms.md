### Fixed

- **A `( mem_dup x )` as an arm of a `?` join hands its copy over**
  (Agora #688). `^ ? c ( mem_dup a ) ( mem_dup b )`, a binding of such a
  join, one handed to a `sink` or pushed, and a `mem_dup` arm beside a
  fresh call or beside the binding it copies were accepted, and the copy
  the chosen arm made was released by nobody: a leak of every String and
  Vec it owned. A join reads each arm's ownership from the arm's call, and
  `mem_dup` is a builtin with no callee to ask; an arm that is the
  `mem_dup` call itself now answers "owned", so the join hands the copy
  over as it does a fresh call's result. (A copy made inside a call the
  arm makes, `( f ( mem_dup x ) )`, is f's argument, as before.)

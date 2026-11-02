### Fixed

- **A call through a closure value or a trait object answers with what the
  code it runs does** (Agora #359, #403, #394; probes closure_*_ends_*,
  closure_*_handed_to_a_function_*, closure_pushing_a_view_*,
  dyn_method_*). A closure literal is now summarised from its own body as
  a function is: what it changes, moves or drops of its parameters, and
  the views it leaves one parameter holding of another. A call through a
  binding holding it is a call of the binding's summary node, the union
  of every closure bound to the name. A closure parameter of a function is
  the union of what every caller passes there. Before, `( clr inner )`
  with `clr = \ ( Vec String ) x → v { ( vec_clear [String] x ) }` ended
  no borrow of `inner`'s elements (heap-use-after-free), and neither did
  the same closure handed to a function that calls it. A closure pushing a
  view of its String argument into its Vec argument left the caller's Vec
  untied to the String. A `dyn` call whose impl stores a view of one
  argument into another left the caller's holder dangling: the virtual
  callee now answers with the union of its impls' holder/source pairs.
  A closure that only reads or pushes into its parameter is accepted as
  before.

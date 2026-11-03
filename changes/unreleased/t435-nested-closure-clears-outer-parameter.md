### Fixed

- **A closure that clears its parameter through a nested closure is
  summarised as clearing it** (Agora #435; probes
  closure_*_its_parameter_through_a_nested_closure*).
  `\ ( Vec String ) x → v { : ( @ v ) g \ → v { ( vec_clear [String] x ) } ( g ) }`
  called with a Vec whose element was still borrowed ended no borrow of
  that element. It is refused now, as the clear written directly in the
  outer body was. A nested reader stays accepted.

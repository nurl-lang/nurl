### Fixed

- **A closure read out of a field, an element or a call's result is
  called as any closure of its type** (Agora #418; probes
  closure_read_out_of_*, closure_returned_by_a_call_*). A clearing
  closure stored in a struct field, pushed into a Vec of closures, or
  returned by a function, then read back and called with a Vec whose
  element was still borrowed, ended no borrow of that element: it was
  read by its interface only. Such a call now answers with every closure
  literal of that type the program builds. A reader stays accepted.

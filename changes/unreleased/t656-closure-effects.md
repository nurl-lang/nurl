### Fixed

- **What a closure changes reaches the summaries its callers read** (Agora #656, #784, #797, #789). These were accepted, and the caller's slice or element view outlived the change (heap-use-after-free):
  - a closure that grows a captured parameter, run in its function, by a helper, or by calling a named grower;
  - a closure the function hands back, run by the caller after it took a view, `@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }`;
  - a closure that captures a local holding the parameter or read out of it (an element, a field, a struct or a Vec the parameter was put into) and clears, grows or replaces through it;
  - a closure that pushes the parameter into a captured local which the function then changes;
  - a closure literal that puts its own parameter into a local, or reads a field or an element out of it (or grows an element of it), and changes that;
  - an inner closure changing a copy of the outer literal's parameter.

  Closures that only read what they captured stay accepted.

### Known issues

- A function's summary covers a closure body whether or not the closure runs there: a caller holding a view across a call that only builds or registers such a closure is refused (as for drops before). A returned closure's effects are not yet carried for a builder declared below its caller or generic, a field-path or lending argument, a join return or an `=` assignment (Agora #802).

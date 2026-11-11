### Fixed

- **An option or a result that a loop body's `;` defer keeps is released
  every round** (Agora #671, `compiler/nurlc.nu`). After Agora #655 a
  String, a Vec, a struct with a destructor or a closure kept by a defer
  inside a loop was parked when the next round bound the name again and
  released at the function's exit; a `?String`, a `!String String` or a
  `?R` beside them was not: every round's value but the last was never
  released, and an `R`'s destructor ran for the last round only. The
  parking asked for the drop of the slot's type, `{ i1, %String }`, but
  an option or a result is registered under its named twin; it now takes
  the type the binding was registered with.

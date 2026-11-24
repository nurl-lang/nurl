### Changed

- **`^ ( same a )`, handing back a local raw string through a function, is accepted whatever order the two functions are written in** (AGORA-867, AGORA-946 D4b). With `a` an `s` the function owns and `same` handing its argument back:
  - **`same` defined above:** the return copied the text for the caller, so the program compiled and ran clean.
  - **`same` defined below:** the same program was refused with "this returns a view of 'a' … released when the function returns".

  Now both compile. When the callee may lend back such an argument, the caller gets the result as its own: the string the callee handed over when it did, a copy of what it lent otherwise. That copy is decided at module end from the callee's summary, as it already is for a `String` or a `Vec`. A callee that lends only a parameter keeps its result a lend of that parameter. A callee that hands back a fresh string hands it over without a second copy. Every program accepted before compiles to the same code.

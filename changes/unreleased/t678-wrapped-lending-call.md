### Fixed

- **A lending call written over several lines borrows from its arguments,
  as the same call on one line does** (Agora #678). A binding whose
  right-hand side hands back an argument's element or field (`vec_at`,
  `vec_get`, a function of the program's own) was matched to the call's
  lend by line number. With an argument on a later line than the `:` head,
  or the whole call on the next line, the binding took no borrow, so a
  `vec_clear` of the source afterwards was accepted and the binding read
  freed memory. Now such a program is refused, with the error its one-line
  twin gets.

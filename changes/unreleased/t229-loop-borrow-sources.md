### Fixed

- **A loop-carried borrow is tracked to every source it may have at the
  loop head** (Agora #229). The checker kept each borrow binding's sources
  as a fact that every walk of a loop body overwrote, so a binding that
  borrows from one source on some passes and another on the rest (a
  cursor pair swapped each pass, as in `stdlib/ext/regex.nu`'s matcher)
  was tracked as borrowing from whichever source the last walk saw. Ending
  the other source and then reading through the binding compiled, and was
  a use-after-free. The loop head now joins the sources of both paths into
  it. Loops also settle without the cycle detector, which no file in the
  tree reaches now.

### Fixed

- **A foreach's element no longer stays bound after its loop** (Agora
  #245). `~ s xs { … }` defined `s` in the enclosing scope, so the
  element could still be read after the loop. If the Vec had been
  cleared, it was a view of a released slot; if the loop never ran, it
  had never been written. Both were memory errors in safe code. It also
  replaced an outer binding of the same name. The element is now bound
  for the body only: after the loop the name is the outer binding again,
  or undefined.

### Fixed

- **A callee that leaves a parameter viewing its own field says so to its
  callers** (Agora #584). A function that stores into a field of its
  `inout` struct a view of another field of the same struct — `= . p w
  @ W { ( string_data . p s ) }`, or the same through a call such as `(
  f . p w . p s )` — left its caller's argument tied to nothing, so
  growing `. p s` after the call and then reading the view read freed
  memory (heap use after free). The function's summary now names the
  field, and the caller's argument depends on that field of itself, as it
  does when the store is written in the caller.
  The tie holds wherever the call is: in a `?` or a loop condition, in a
  return, or beside another call in the same statement that grows the
  field. A closure that has a function leave one of its captures viewing
  its own field is refused, as a view stored into a capture is.

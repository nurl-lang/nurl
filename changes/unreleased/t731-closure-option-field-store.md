### Fixed

- **A field store inside a closure drops the option value it replaces**
  (Agora #731). `= . h o @ ?T { … }` in a closure body, over a struct the
  closure captured by pointer or one of its own, left the old option's
  payload to nobody: every store leaked it (a `String`, `Vec` or handle
  field was released; an option or a result of one was not). It is
  dropped now under the capture's owner flag, as a handle field's old
  value is.

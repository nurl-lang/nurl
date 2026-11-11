### Fixed

- **A `% Drop` value more than eight containers deep is dropped**
  (Agora #660). Whether a type holds a value with a destructor of the
  program's own was asked with a depth limit of eight: a struct whose
  field was a `Vec` of `Vec`s nine deep around such a value got no drop
  of its fields, the destructor never ran and everything on the way to it
  leaked. The question is a search over the type now, each type asked
  once.

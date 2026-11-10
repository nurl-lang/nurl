### Fixed

- **A view of a String field reader's bytes ends when that field grows**
  (Agora #396). `: String f . t name`, `( vec_push [s] o ( string_data f ) )`
  and later `( string_push_str . t name … )` kept `o` viewing the moved-out
  buffer: a heap-use-after-free. The view was recorded as reaching `t` only
  through an element (`^t`), whose buffer stays put, but a field viewer's
  bytes are the field path's own buffer. A view of a field viewer now has
  the field path itself as its source (its `fp_`). A push into `. t name`
  ends it, while a push into another field of `t` does not.

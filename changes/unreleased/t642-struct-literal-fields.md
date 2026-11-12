### Fixed

- **Struct literals with a `% Drop` field: a closure field freed once, a
  literal handed to a reader dropped, a panic mid-literal releases the
  fields made** (Agora #642).
  - A struct with a `% Drop` field and a closure field freed the closure's
    environment twice when it was dropped: once by the struct's own drop,
    once by a registration of the field's own. That was a heap-use-after-free
    in safe code with no panic, and a struct moved through a `Vec`
    (`vec_pop`, then `vec_push`) faulted the same way. Such a struct can
    now also be moved to another binding or handed to a `sink` parameter;
    both were refused, because the closure field counted as a raw owned
    field.
  - Such a literal handed straight to a function that only reads it now
    runs its `% Drop` fields' destructors after the call. Before, it
    released only their `String`s, `Vec`s and handles.
  - Under `recover`, a literal whose later field's expression panics now
    releases the fields it had already made.

### Fixed

- **A field of a match payload handed to a `sink` is a copy for the
  callee** (Agora #357). `?? ( vec_get [H] vs 0 ) { T p → ( take . p buf ) }`
  emptied the field in the Vec slot to a null handle, and a later
  `vec_get` of the element crashed on it. With a user enum's payload,
  the enum kept the buffer the callee freed (heap use after free). The
  callee now gets a copy where it takes the field, as for a `vec_at`
  element, and the element keeps its own.
  A callee that stores the field keeps its own copy, as before, and
  `string_free . p s` on such a payload frees a copy: the element keeps
  its string, as with `vec_at`. Option-typed fields are still open
  (Agora #559).

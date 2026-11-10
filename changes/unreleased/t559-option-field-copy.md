### Fixed

- **An option field, or an enum payload's field bound to a local, of a lent
  match payload is copied for a consuming callee** (Agora #559). #357
  covered handle fields only. A `?String` field of a `vec_get` or enum
  payload handed to a `sink` was freed by the callee while the owner kept
  it (heap use after free), and so was `: x . p buf  ( take x )` over an
  enum payload. Both are copies for the callee now.

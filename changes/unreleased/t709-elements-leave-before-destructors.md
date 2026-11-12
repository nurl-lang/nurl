### Fixed

- **A destructor that pushes into the `Vec` or `Deque` it is being dropped
  out of no longer corrupts it** (Agora #709). `vec_clear`,
  `vec_truncate`, `vec_retain` and `deque_clear` shortened the
  container's count and then dropped the elements out of its own buffer.
  A destructor that reached the container (an `Rc` of it held by its
  elements, a `Weak` upgraded) and pushed wrote over the next element to
  go, which was never dropped. The release then dropped the pushed element
  while the container still held it, and a push that grew the buffer freed
  the storage the release was walking: a heap-use-after-free in safe code,
  no panic needed. For element types whose drop runs code of the program's
  own, the elements to go now move into a buffer of their own before the
  first destructor runs. Every element is dropped once, in index order,
  and what a destructor pushes stays in the container. That costs one small
  allocation per release (+1–2 % for a loop of truncates and clears over
  elements with trivial destructors). Every other element type is released
  exactly as before.

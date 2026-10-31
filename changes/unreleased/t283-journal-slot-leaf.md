### Changed

- **A binding's panic-journal registration is cheaper** (Agora #283, part
  1). Inside a recover extent (every HttpApp handler), every owned binding
  registers its slot with the drop journal. The registration's body also
  held the rare grow-the-stack path, so it saved and restored six
  callee-saved registers on every call. The grow path is now a cold
  tail-call of its own, and the registration is a leaf. A handler-shaped
  microbenchmark (owned structs, Vecs and Strings in a loop under
  `recover`) runs 4.4 % fewer instructions (229.4 M → 219.2 M).

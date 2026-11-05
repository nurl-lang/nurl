### Fixed

- **A library handle whose first field is a `( Locked T )` compiles
  again.** A binding read out of a field of a struct that may have changed
  is checked against the field's current value by the identity of a
  library handle: its control-block pointer. The pointer was taken from
  field 0, or from field 0 of a `( Shared T )` there. A `Locked` is a
  Shared of its own, two levels above the pointer, so for gpukit's
  `GpuKit` the check compared the `Locked` struct itself as a pointer,
  and clang rejected the program. nurllama did not compile. The key now
  follows every one-field wrapper down to the pointer, and a handle whose
  field 0 ends at no pointer has no identity to compare.
  `compiler/tests/libh_key_locked_first.nu` reproduces it.

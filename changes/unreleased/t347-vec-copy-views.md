### Fixed

- **A copy of a Vec of views keeps the views' sources** (Agora #347).
  `vec_extend`, `vec_extend_range`, `vec_clone` and `slice_to_vec` copy
  each element, and a copy of a view is the same view. But their summaries
  said they kept nothing, so an outer Vec given the copies of a block-local
  `( Vec s )` was read after the String the views pointed into was freed
  (heap-use-after-free in safe code). The same happened inside a closure
  that extended a capture or gave it a clone of its parameter.
  - The compiler now infers, for any function, which arguments' views it
    copies: an element read through a pointer into one parameter's buffer
    and stored through another, for an element type that can hold a view.
  - The destination (for vec_extend and vec_extend_range) and the result
    (for vec_clone and slice_to_vec) then depend on what the argument's
    elements view.
  - Copies of a `( Vec String )` copy each element deep and are accepted
    as before. A copy that outlives only the source Vec, not the Strings,
    stays accepted too.

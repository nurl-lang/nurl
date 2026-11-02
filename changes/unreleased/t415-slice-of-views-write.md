### Fixed

- **A view is not stored into a Slice's elements** (Agora #415; probes
  view_stored_into_a_slice_element, view_copied_into_a_slice_from_another).
  `( slice_put [s] sl 0 ( string_data loc ) )`, with `sl` a slice of a Vec,
  or a `slice_copy` from a Vec holding a view, recorded no dependency at
  all. So the Vec, or the slice, read after `loc` ended read freed memory.
  Writing a Slice whose elements hold views is now refused outside
  `unsafe`. The message points to the Vec that owns the storage (`vec_put`,
  `vec_set`, whose stores are followed). Reading a Slice of views, and
  writing a Slice of owned values, are unchanged.

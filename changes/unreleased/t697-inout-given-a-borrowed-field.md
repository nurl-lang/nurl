### Fixed

- **An `inout` parameter given a field of a value it does not own gets a
  copy** (Agora #697). `= dst . x v`, with `x` a parameter the function
  only borrows (or an `inout` one, a cursor over one, a field two deep, a
  field of an element `vec_at` lends), stored the field's handle in the
  caller's binding as is: the caller then held two owners of one buffer,
  and growing one freed what the other read. The field is copied there
  now and the caller's old value released, as it already was for a field
  of the function's own local. A field taken out of a fresh temporary is
  the caller's own and is not copied; a `% Drop` field with no clone is
  refused where it is read.

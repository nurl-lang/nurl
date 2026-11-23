### Changed

- **A `:` join reading an inner struct's field can be handed to an `inout` parameter** (AGORA-959). `: y ? c . p s ( mk )` then `= t y`, with `t` an `inout` String, Vec, option or struct parameter, was refused as storing a view of `. p s` into the caller's storage. The generated code already gives the parameter a copy wherever the join lends, so the program is safe and now compiles. A value that cannot be copied (a `% Drop` struct) is still refused.

  The parameter holds a copy, so a later call that may panic no longer reads it as a view of the struct. Where the join lent, the binding stays readable; where it owned, it moved. A struct of views or a `Vec` of views is still refused: the copy is shallow, so the views would still point into the local.

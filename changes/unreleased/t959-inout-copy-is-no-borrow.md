### Changed

- **A `:` join reading an inner struct's field can be handed to an `inout` parameter** (AGORA-959). `: y ? c . p s ( mk )` then `= t y`, with `t` an `inout` String, Vec, option or struct parameter, was refused as storing a view of `. p s` into the caller's storage. The generated code already gives the parameter a copy wherever the join lends, so the program is safe and now compiles. A value that cannot be copied (a `% Drop` struct) is still refused.

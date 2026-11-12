### Fixed

- **A `% Drop` value lent by a call and handed to a function that changes
  it ends the views of what lent it** (Agora #692). `( rg ( vec_at [R] rs 0 ) )`,
  with `R` a struct with its own `% Drop` and a `Vec` field that `rg`
  grows, was not traced back to `rs`. A Slice of that Vec taken before the
  call read freed memory after it. A helper doing it carried no change of
  `rs` in its summary, and through `arc_get` the frozen-Arc rule did not
  see it, so eight threads could grow one Vec. Without the `% Drop` all of
  these were refused, and now they are refused with it too.

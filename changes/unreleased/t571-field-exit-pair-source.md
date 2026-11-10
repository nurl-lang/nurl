### Fixed

- **A callee that points a holder at a struct field ties the holder to
  that field** (Agora #571). `( f . p w . p s )` or `( f w . p s )`, with
  `f` storing a view of its `inout String` parameter into its holder
  parameter, left the holder tied to nothing, so growing `. p s` and then
  reading the holder read freed memory (heap use after free). The field
  is now the pair's source, as a whole binding `( f w s )` already was.

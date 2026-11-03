### Fixed

- **A function storing a local copy of its view parameter into an `inout`
  holder ties the holder to the caller's value** (Agora #346; probes
  function_stores_a_local_copy_of_its_view_parameter_*).
  `@ setw inout V w s p → v { : s t p  = w @ V { t } }` gave the caller no
  record that `w` views what `p` views, and the caller read freed memory
  once its String ended. The direct `= w @ V { p }` was refused. This form
  is now refused too, and accepted while the String lives.

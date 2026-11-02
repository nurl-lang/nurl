### Fixed

- **A `\` that hands a failure back is checked as a way out** (Agora #379;
  probes inout_holder_*try_exit*). `@ fill inout W w i k → !i E { : String
  b … = w @ W { ( string_data b ) }  : i x \ ( may k )  = w @ W { `literal`
  } … }` handed `w` back viewing the released `b` whenever `may` failed: a
  `\` exit had none of the checks a `^` and the body's end make. It now
  has them (after the defers that run there), and the success path goes
  on as before.

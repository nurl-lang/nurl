### Fixed

- **An `inout` holder whose view a buffer move ended is refused at the way
  out** (Agora #390). `@ f inout W w inout String s → v { = w @ W { (
  string_data s ) } ( string_push_str s … ) }` handed `w` back to the
  caller viewing the bytes the push moved away from. The walk had ended
  `w`'s view at the push, but a parameter is never released, so nothing
  asked about it again. Every way out now refuses an `inout` parameter in
  that state, naming the line that ended its view and what to do.

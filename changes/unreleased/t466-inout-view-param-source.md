### Fixed

- **An `inout` view parameter is a source of its own** (Agora #466). A
  view parameter stands for what its caller passed, so a holder given it
  is tied to that argument by the function's answers (`pv_`, #341). An
  `inout` one (`inout s x`, `inout W w` of views) stood for nothing.
  `( vec_push [s] h x )` into a second `inout` holder, `= g_err x` into an
  `s` global and a thread capturing `: s msg x` went unchecked, and the
  caller's holder outlived the String (heap-use-after-free). Now it
  stands for the caller's argument too. Given a new value, a view's own
  sources take over; given a literal, it still stands for the argument,
  which only refuses more. An `inout` view parameter only read, or
  re-pointed with nothing stored, is accepted as before.

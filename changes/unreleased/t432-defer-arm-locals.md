### Fixed

- **A defer in an arm not taken leaves the values its body would have
  bound alone** (Agora #432; test defer_in_an_arm_not_taken). Take `? c
  { ; { : ( Vec i ) g ( vec_new [i] ) … } } {}` with `c` false. The
  defer is never armed, but fn_cleanup still released `g` from a slot
  nothing had filled (a misaligned read, or a crash). An owner bound in a
  defer body now gets a drop flag cleared at the function's entry. The
  snapshot fn_cleanup reclaims from carries each owner's flag, even where
  the arm that named it has closed.

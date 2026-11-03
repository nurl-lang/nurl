### Fixed

- **A temporary argument the callee does not hand back is released**
  (Agora #457; probes *temporary_not_handed_back*). `( maybe ( string_from
  … ) 1 )`, with `maybe` handing back its argument on one path and a fresh
  value on another, never released the temporary on the run that handed
  back the fresh value. The caller now asks the call's own answer: where the
  result is the callee's own, the temporary goes after the call; where the
  callee lent it back, it is the result. This covers String, Vec and handle
  temporaries; option temporaries, two-argument pickers and `\` paths are
  still open under #457.

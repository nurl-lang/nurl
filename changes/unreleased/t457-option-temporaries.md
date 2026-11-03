### Fixed

- **An option temporary the callee does not hand back is released**
  (Agora #457; probes option_temporary_not_handed_back_*). The fix for
  String and Vec temporaries now covers an option or result temporary
  too: `( maybe ( mk … ) 1 )`, with `maybe ?String a i k → ?String`, no
  longer leaks the temporary's payload on the run that hands back a fresh
  option.

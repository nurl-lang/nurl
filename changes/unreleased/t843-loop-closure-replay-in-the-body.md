### Fixed

- **A closure given a changing literal below its run in a loop ends a view
  read after the run on the next round** (Agora #843). In
  `~ … { ( d ) … read sl … = d \ → v { ( rc_set r … ) } }`, the next round
  runs the literal assigned below. #686 replayed its effects for the code
  after the loop only. A view read inside the body, after the run, read
  freed memory on the next round; so did one read through a struct whose
  closure field is given the literal below the helper's run, and the
  same in a loop over a Vec. These are refused now, as the body's own
  call written there is. A closure that only reads still compiles.

### Fixed

- **A value block's tail join whose arm is itself a join of its locals**
  (Agora #836): `: String e { : String s … t … u … ? a s ? b t u }`, a `??`
  arm `? c s t`, and deeper nestings leaked the locals each round; a
  `% Drop` struct or an `=` target in a loop read freed memory. The
  selected local now moves into the block's value on its path.

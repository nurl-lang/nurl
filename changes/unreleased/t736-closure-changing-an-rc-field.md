### Fixed

- **A closure that changes an Rc a captured struct holds ends the views
  through other handles** (Agora #736). `( rc_set . h a … )` or
  `( vec_reserve ( rc_get . h a ) … )` written in place was refused beside
  a slice of the same payload read through another handle. Inside a
  closure, called here or by a function it was handed to, it compiled,
  and the slice read freed memory. It is refused now, naming `. h a` and
  the Rc it may share. A closure that only reads the payload, or changes
  an Rc of another type, still compiles.

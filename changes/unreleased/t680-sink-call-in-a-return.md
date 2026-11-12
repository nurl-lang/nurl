### Fixed

- **A call in a returned expression is checked as the same call in any
  other statement is** (Agora #680). `: Col c ( vec_at [Col] cs 0 )` then
  `^ ( keep . c name )`, with `keep` a `sink`, was accepted, and so were
  `^ + 1 ( keep . c name )` and the call as a function's last expression.
  The field was freed while the `Vec` still owned it, and freed again by
  the `Vec`. Each is refused now, as `: i n ( keep . c name )` already
  was.

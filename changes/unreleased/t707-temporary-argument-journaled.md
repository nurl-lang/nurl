### Fixed

- **A call's result passed straight as an argument is dropped when the
  callee panics** (Agora #707). `( boom ( bomb … ) 1 )`, with `bomb`
  returning a struct that has its own `% Drop` (or an option of one) and
  `boom` panicking under `recover`: the temporary is the caller's until the
  call returns, but only a `String`, `Vec` or library-handle temporary was
  in the panic journal for that window. The unwind now runs the
  temporary's destructor, once, wherever it sits among the arguments.

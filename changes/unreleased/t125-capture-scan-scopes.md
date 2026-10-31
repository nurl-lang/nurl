### Fixed

- **A name a closure body binds itself no longer captures the outer
  binding it shadows** (Agora #125). The closure capture scan had no
  scopes: after `: i w 3`, in an arm `T w → …`, or inside a nested
  closure `\ i w → i { … }`, a `w` the body read was taken for the outer
  `w`. A thread's closure then moved the spawner's Vec it never touched
  (the spawner's next use was refused: "use of moved value 'w' — consumed
  by the closure that 'thread_spawn' runs"), a closure that stays local
  copied it into its environment for nothing, and `= w …` on the inner
  binding was refused as "cannot mutate immutable variable 'w'" when the
  outer one was immutable. The scan now follows the expressions it walks:
  a `:` binding's name is bound once its value ends (`: i w + w 1` still
  reads the outer `w`), an arm's payload names in its guard and result,
  and a nested closure's parameters in its body. Where it cannot follow an
  expression it captures, as before.

### Fixed

- **A closure no longer captures an outer binding that a select arm's
  result name or a foreach's element shadows** (Agora #238, after #125).
  `?? { [i] ch → w { … } }` and `~ w xs { … }` bind `w` for their block.
  The closure capture scan took that `w` for the outer one. A thread's
  closure then moved a Vec it never touched, and the spawner's next use
  was rejected. The outer binding is still captured wherever the body
  reads it.

### Fixed

- **An arm's own locals are released when its tail call lends something
  else** (Agora #662 items 1, 2 and 6c; #771). `? c { : String junk ( mk 2
  ) ( first outer junk ) } …` — a tail call handed one of the arm's locals
  that lends another argument — kept the arm's locals past its exit, and
  so did a tail call lending a field of an outer binding (`( idg [String]
  . o name )`) and one lending a field of the arm's own struct: they leaked
  once per run of the arm. After the copy the arm makes where the call may
  lend one of its own, the arm now asks the callee whether it lends
  anything else the arm owns, and a field path counts as its root binding.

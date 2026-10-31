### Changed

- **formal: a binding with a destructor takes no premise on its body's
  typing (Agora #243).** A2-drop.1's `StmtT.letd` asked of its body's
  typing what the panic step needs (`KeepOut`, `CtxWF`, `NameWF`). That
  restricted which programs the calculus typed. Now one lemma gives all
  three for every source body: source typing keeps every binding with its
  mode and type, and a borrowed parameter whose sources are lent out with
  its entry (`StmtT.ctxRel`, `formal/A2/SrcKeep.lean`). `letd` types every
  body the other rules type, and `memory_safe`, `no_leak_end` and
  `no_leak_panic` still rest on the standard axioms only.

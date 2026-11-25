### Fixed

- **A certificate's claims cover every run of the program, not only the run in which every number is 0** (AGORA-1030). The core IR records what a program does with memory, not the numbers it computes.
  - **What was wrong:** the translation wrote each untracked number as `.lit 0`. That covers every condition, loop condition, index and computed value. A2's semantics is deterministic, so a certificate's model took the else arm of every `if`, and its `M.safe`, `M.leak` and `M.race` covered that single run. The checker's verdict, which types every arm, was the same.
  - **The fix in the model:** A2 has a new expression, `Expr.any`, a number the model does not track, of any value (`Eval.any`). Every proof gains its case, and no theorem changes.
  - **The fix in the translation:** an untracked number is now `.any`, and a computation over tracked operands is any number with those operands still read. The model's runs include every run the program can make. `C.ite_any_both` shows both arms of a condition on such a number are steps of the model.
  - **Unchanged:** every certify and hole probe keeps its verdict, and kernel time is the same.
  - **Breaking:** a bundle made by nurl-cert 0.1.0 (v0.95.0) claims less than its sentences say. Certify it again; `verify` refuses it, since its `formal/` tree hash differs. The parity check with the frozen `tools/ncore/tolean.py` compares modulo `.any` (`tools/ncore/norm_any.py`).

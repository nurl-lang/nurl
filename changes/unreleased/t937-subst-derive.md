### Changed

- **The formal proof's region substitution commutes with deriving a borrow** (AGORA-937, stage 3c, second part). Composing dependency kinds is associative (`comp_assoc`). So deriving a borrow and then replacing its region dependencies gives the same result as replacing first and then deriving (`subDc_derive`). The context the memory invariant is stated of therefore follows the body's borrows step for step. No typing rule uses it yet, and every theorem statement is as it was. Compiler, runtime and NURL source are unchanged, so compile time and run time are byte-for-byte as before.

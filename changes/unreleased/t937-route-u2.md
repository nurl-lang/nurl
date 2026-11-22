### Changed

- **Formal proof design: route U's conditions become memory-invariant clauses, not new typing premises** (AGORA-937). A root that a lent parameter views without it being frozen must be named by no variable of the running statement. A `Vec` borrow among those variables may reach it only inside its elements. The call that places the callee establishes both. No typing rule gains a premise, and nothing changes in nurlc.

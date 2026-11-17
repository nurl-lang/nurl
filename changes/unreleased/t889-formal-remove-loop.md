### Changed

- **The formal proof types a remove of a number at a general index through a borrow** (AGORA-889). `formal/A2/RemoveLoopWitness.lean` reads `( vec_remove b i )` through a `vec_at` borrow as a loop. Each later element is set one place down, then the Vec is truncated. It proves the program memory-safe and leak-free for every index, with A2's existing rules. AGORA-888 had typed only an unrolled three-element case. Moving an element that owns memory out through a borrow, and keeping it, is still outside the claim, as `formal/CLAIM.md` says.

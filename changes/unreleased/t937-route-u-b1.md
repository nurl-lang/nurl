### Changed

- **Formal model: a change through a borrow must end no lent `Vec`'s view of the root it changes** (AGORA-937). The typing rule now states this outright, where before it followed from the root being frozen. Every program that typed before still types, and nurlc already refuses such a change. The rename lemma and the memory invariant carry the new condition. This is route U's second step.

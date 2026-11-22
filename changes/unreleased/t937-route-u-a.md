### Changed

- **Formal proof: the memory invariant now allows a lent `Vec` to hold views anchored at a root that is changed only inside its elements** (AGORA-937). Every lemma that ends bindings shows it spares those views. Where the statement runs, anchors stay frozen as before, so no typing rule changes and nothing changes in nurlc. This is route U's first step. The call that sets up such views comes next.

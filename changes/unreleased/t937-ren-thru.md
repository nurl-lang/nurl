### Changed

- **The formal proof can now place, inside the caller, a callee's change through a parameter whose argument views the caller's memory** (AGORA-937). This holds when all of the following are true:
  - the argument views each root only directly;
  - no other argument reaches that root;
  - the root is a live `Vec` the caller owns;
  - no other binding of the caller's frame views inside the root's elements, which the call's entry kill guarantees;
  - the call freezes nothing else;
  - the statement calls no through-changing function.

  Under these conditions the caller ends exactly the bindings the callee's change would end. The call rule that grants these conditions is still to come. Nothing changes in nurlc, and the proof is complete with no theorem weakened.

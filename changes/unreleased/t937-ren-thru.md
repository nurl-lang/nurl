### Changed

- **The formal proof can now place, inside the caller, a callee's change through a parameter whose argument views the caller's memory** (AGORA-937). This works when the call meets a set of conditions:
  - the argument views each root only directly;
  - no other argument reaches that root;
  - the root is a live `Vec` the caller owns;
  - the call freezes nothing else.

  Under these conditions, the caller ends exactly the bindings the callee's change would end. What remains is the call rule that grants these conditions. Nothing changes in nurlc, and the proof is complete with no theorem weakened.

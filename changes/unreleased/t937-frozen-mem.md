### Changed

- **Formal proof: a frozen owner may be changed strictly inside its elements, as far as memory is concerned** (AGORA-937). The memory invariant is now proved to survive such a change when two things hold:
  - no lent parameter reaches that owner through its path, and none but a `Vec` through what it holds. So every lent parameter's node lies in another frozen owner's tree or in a live block's payload;
  - the change ends no loan.

  The typing rule that would allow such a change is still to come. It waits on how the proof treats frozen bindings across a step, which the design notes record. Nothing changes in nurlc.

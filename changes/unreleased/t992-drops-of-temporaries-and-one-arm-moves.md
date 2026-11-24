### Added

- **The drop validation checks temporaries and one-arm moves against the core IR** (formal phase D0d, AGORA-992). `tools/ncore/tv.sh prog.nu --ir` now also asks two things:
  - **a temporary the core IR never moves**, one bound straight from a call, is not handed on by the LLVM: not to a `sink` or `keeps` argument, not by `ret`, not into an aggregate, not into memory outside the frame. It is matched to the LLVM by its call, the k-th of the function's calls to that callee, where both have as many;
  - **a binding the core IR moves on one arm of an `if` only** is handed on in that arm's LLVM blocks only.

  Over the corpus this checks 2818 temporaries and 294 one-arm bindings, with no mismatch. `tools/ncore/tv/selftest.sh` gains a case for each. Its edits now read the registers they change from the emitted LLVM, so a change of nurlc's register numbering no longer turns them into no-ops: 15 of its checks had stopped applying, and all 60 pass now.

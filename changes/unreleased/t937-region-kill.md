### Changed

- **The formal proof now shows that a change inside a region's elements, placed in the caller, ends exactly what the callee's change ends** (AGORA-937). When a callee changes memory inside the elements its argument views, the caller sees that change on the argument's root. The caller then ends the same bindings the callee does. It ends no frame binding, given the conditions the coming call rule will ask for. These lemmas are the core of typing such a call. Nothing changes in nurlc, and the proof is complete with no theorem weakened.

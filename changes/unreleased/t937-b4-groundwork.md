### Formal

- **A2 groundwork for typing a call that changes memory its arguments view, inside the elements** (AGORA-937 B4, AGORA-933's `( f1 vv )`).
  - New definition `CallThruOK`, the call-site premise route U will add.
  - `zN` leaves out the roots such a call changes inside. That set is empty for every call typed today.
  - New lemmas: `StmtT.keepKV` (a binding none of a statement's killable names stays bound), `CallH.thruReady` (a `CallThruOK` call sets its callee's body up ready for a change through its regions) and `CallH.held_anch` (the lifted lent parameter's view of such a root is a held anchor).
  - No typing rule changes, and nurlc is unchanged.

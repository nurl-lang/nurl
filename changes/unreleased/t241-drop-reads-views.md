### Changed

- **formal: a `% Drop` destructor that reads views is inside the calculus
  (A2-drop.2, Agora #241).** A2-drop.1 covered destructors of types that
  hold no views. Now `letd` takes any owned value whose type holds no
  closure. A binding whose type holds views is armed: its destructor reads
  those views at its scope's end and on the panic path. #224's rule
  (`DtorSafe`) keeps what they point into alive on every path where the
  binding may own its value. A new invariant (`MInv.armed`) keeps the
  views valid whenever the slot owns a value, and the unwind hands them to
  the destructor. A binding `letd` made gains no view: assigning to it is
  refused, as is pushing a view into it or passing it as an `inout`
  argument. `A2.memory_safe`, `A2.soundness`, `A2.no_leak_end` and
  `A2.no_leak_panic` are re-proven (`formal/check.sh`, Lean 4.35.0,
  standard axioms only). `formal/CLAIM.md` no longer lists destructors of
  view-holding types as outside the proof. What stays is A2-drop.3
  (Agora #253): a value moved out of its `letd` binding is still released
  without its destructor in the calculus.

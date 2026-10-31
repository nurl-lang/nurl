import A3.Nid

/-! A3.0 — the relations the frame layer is stated with.

A thread's step runs on the shared address space (`Cfg.view`); A2's facts
about the thread hold on its own part of it.  A step on one is a step on
the other, with the address space changed by the other threads' part
(`minus` / `union`).  The one thing a step stores that sees the address
space is the store a `recover` frame remembers (`Step.letrec`'s
`catchR x m0`): on the two views it differs in `alloc` only, which no step
reads (`catchP` restores bindings from the unwound store, not from `m0`).
`GhostRel` is equality but for that. -/

namespace A3
open A2

/-- `a` without the addresses of `b`. -/
def minus (a b : Nat → Bool) : Nat → Bool := fun i => a i && !b i

/-- `a` and `b` together. -/
def union (a b : Nat → Bool) : Nat → Bool := fun i => a i || b i

/-- An address in a tree one of `m`'s owned slots holds. -/
def OwnedId (m : Mem) (i : Nat) : Prop := ∃ x t, OwnedAt m x t ∧ i ∈ t.ids

/-- No owned tree of `m` has an address of `a2`. -/
def Avoids (m : Mem) (a2 : Nat → Bool) : Prop := ∀ i, OwnedId m i → a2 i = false

/-- `a2` has no address at or past `n`. -/
def FreshFrom (a2 : Nat → Bool) (n : Nat) : Prop := ∀ i, n ≤ i → a2 i = false

/-- Two statements equal but for the stores their `recover` frames
    remember: the second's has the same bindings, `nv` and `nid`, and every
    address live in the first's. -/
inductive GhostRel : Stmt → Stmt → Prop
  | refl (s : Stmt) : GhostRel s s
  | seq {a a' : Stmt} (b : Stmt) : GhostRel a a' → GhostRel (.seq a b) (.seq a' b)
  | scope (x : Var) {s s' : Stmt} : GhostRel s s' → GhostRel (.scope x s) (.scope x s')
  | scopeD (x : Var) (f : Nat) {s s' : Stmt} : GhostRel s s' → GhostRel (.scopeD x f s) (.scopeD x f s')
  | rbind (p : Var) {s s' : Stmt} : GhostRel s s' → GhostRel (.rbind p s) (.rbind p s')
  | frozen (z : List Var) {s s' : Stmt} : GhostRel s s' → GhostRel (.frozen z s) (.frozen z s')
  | catchR (x : Var) {m0 m0' : Mem} {s s' : Stmt} :
      m0'.st = m0.st → m0'.nv = m0.nv → m0'.nid = m0.nid →
      (∀ i, m0.alloc i = true → m0'.alloc i = true) →
      GhostRel s s' → GhostRel (.catchR x m0 s) (.catchR x m0' s')

/-- `r1` is the step `r` on the thread's own part: the same outcome, the
    address space without `a2`, and the same statement but for the stores
    of `recover` frames (`r1`'s remember the smaller address space). -/
def ResDown (a2 : Nat → Bool) : Res → Res → Prop
  | .ok m s, .ok m1 s1 => m1 = { m with alloc := minus m.alloc a2 } ∧ GhostRel s1 s
  | .panic m, .panic m1 => m1 = { m with alloc := minus m.alloc a2 }
  | _, _ => False

end A3

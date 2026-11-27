import C.Caps
import C.Cert3
import A3.Reach

/-!
# C16, threads: what a threaded program can run (AGORA-1013)

`C/Caps.lean`'s check (`capsOKB`) for a program that spawns threads: the
same list, closed under the program's names, holds every function any
thread of any interleaving names (`A3/Reach.lean`). Apart from
`C/Caps.lean` so that a single-threaded program's certificate loads no A3.
-/

namespace C
open A2

/-- Every configuration an interleaving of an accepted program's threads
    reaches names only functions of `L`, on every thread and in the shared
    blocks. -/
theorem caps3_names {P : Prog} {s : Stmt} {L : List Nat} (h : capsOKB P s L = true)
    (spawn : Nat → Bool) (nv : Nat) :
    ∀ C, A3.Reach P spawn (A3.Cfg.init s nv) C → A3.CfgFns (· ∈ L) C := by
  obtain ⟨hs, hP⟩ := capsOKB_parts h
  exact fun C hr => hr.fns hP (A3.cfgFns_init hs nv)

/-- **`N.cap`'s theorem for threads: a function outside `L` runs on no
    thread.** Any program with the same functions at the indices of `L` has
    exactly the interleavings of `P` from `s`. -/
theorem caps3_runs {P : Prog} {s : Stmt} {L : List Nat} (h : capsOKB P s L = true) {P' : Prog}
    (hag : ∀ f ∈ L, P'[f]? = P[f]?) (spawn : Nat → Bool) (nv : Nat) (C : A3.Cfg) :
    A3.Reach P spawn (A3.Cfg.init s nv) C ↔ A3.Reach P' spawn (A3.Cfg.init s nv) C := by
  obtain ⟨hs, hP⟩ := capsOKB_parts h
  exact A3.reach_agree_iff hP hag (A3.cfgFns_init hs nv)

end C

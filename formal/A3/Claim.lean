import A3.SpawnPres
import A3.Restrict
import A3.Lift
import A3.SpawnOld
import A3.SpawnNew

/-! A3.0 — the claim. -/

namespace A3
open A2

/-- **A3.0**, and **A3.1** (`Arc`): a program A2 types, whose spawned
    functions take only view-free `sink` parameters, is memory-safe,
    race-free and leak-free on every interleaving of its threads — (A3.6)
    run with its module globals set at start, every thread reading them, and
    leaving at the end only what they reach. -/
theorem claim : Claim :=
  claim_from
    (fun _ => fun h => fun hav hb hp hf => Step.restrict h hav hb hp hf)
    (fun _ => fun h => fun hd hf => Step.lift h hd hf)
    (fun _ _ hP hPc hS => fun hok => fun hR hsp hf hx hmv => spawner_ok hP hPc hS hok hR hsp hf hx hmv)
    (fun _ _ hP hS => fun hok => fun hR hsp hf hmv => spawn_args hP hS hok hR hsp hf hmv)
    (fun _ _ hP hPc hS => fun hsp hf => fun hlen hwf hnd hdisj hself hpk hcd => fun hpart => fun hlt =>
      fun hsh hB hBv => newThread_ok hP hPc hS hsp hf hlen hwf hnd hdisj hself hpk hcd hpart hlt hsh hB hBv)
    (fun _ => fun hok => fun hR => spawnFail_ok hok hR)

/-- A3.6 with no module global, A3.0–A3.5's start: nothing is left allocated
    once every thread has finished. -/
theorem no_leak_init {P : Prog} {spawn : Nat → Bool} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) :
    ∀ C, Reach P spawn (Cfg.init s nv) C → (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = false :=
  NoLeak.empty (claim P spawn Globs.empty s Δ nv hP hPc hSp GlobsOK.empty ht hs hsc hv).2.2

end A3

import A3.SpawnPres
import A3.Restrict
import A3.Lift
import A3.SpawnOld
import A3.SpawnNew
import A2.ArcDtorWitness
import A2.ArcPanicWitness

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
      fun hsh hB hBc hBv => newThread_ok hP hPc hS hsp hf hlen hwf hnd hdisj hself hpk hcd hpart hlt hsh hB hBc
        hBv)
    (fun _ => fun hok => fun hR => spawnFail_ok hok hR)

/-- A3.6 with no module global, A3.0–A3.5's start: nothing is left allocated
    once every thread has finished. -/
theorem no_leak_init {P : Prog} {spawn : Nat → Bool} {s : Stmt} {Δ : Ctx} {nv : Nat}
    (hP : ProgOK P) (hPc : ProgCodes P) (hSp : SpawnOK P spawn)
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P)
    (hv : ∀ v ∈ s.vars, v < nv) :
    ∀ C, Reach P spawn (Cfg.init s nv) C → (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = false :=
  NoLeak.empty (claim P spawn Globs.empty s Δ nv hP hPc hSp GlobsOK.empty ht hs hsc hv).2.2

/-- Agora #610, the witness (`A2.ArcDtorWitness`): an `Arc` of a destructor
    value, cloned, both shares dropped, on one thread.  The claim covers it:
    safe, race-free and leak-free on every interleaving.  (Agora #755 item 1:
    on A3's threads as on A2's, the last share's drop leaves the block an
    orphan that the configuration's marking sweep marks and the same thread
    reaps, running the destructor: `A3.arcDtor_reaps`, on any thread of any
    configuration, as `A2.ArcDtorWitness.last_drop_reaps` on A2's `Steps`.) -/
theorem arcDtor_claim :
    MemorySafe A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcDtorWitness.main 5) ∧
      RaceFree A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcDtorWitness.main 5) ∧
      NoLeak A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcDtorWitness.main 5) := by
  obtain ⟨Δ, ht⟩ := A2.ArcDtorWitness.main_typed
  exact claim _ _ Globs.empty _ Δ 5 A2.DtorWitness.prog_ok A2.DtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl A2.ArcDtorWitness.main_codes (by decide)

/-- Agora #755, the witness (`A2.ArcDtorWitness.mainV`): an `Arc` of a `Vec`
    of destructor values, cloned, both shares dropped, on one thread.  The
    claim covers it: safe, race-free and leak-free on every interleaving.
    (As for `arcDtor_claim`, the thread that drops the last share reaps the
    `Vec`, `A3.arcVecDtor_reaps`, and its frame drains it,
    `A2.ArcDtorWitness.reapV_drains`; on A2's `Steps`,
    `A2.ArcDtorWitness.last_dropV_reaps`.) -/
theorem arcVecDtor_claim :
    MemorySafe A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcDtorWitness.mainV 6) ∧
      RaceFree A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcDtorWitness.mainV 6) ∧
      NoLeak A2.DtorWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcDtorWitness.mainV 6) := by
  obtain ⟨Δ, ht⟩ := A2.ArcDtorWitness.mainV_typed
  exact claim _ _ Globs.empty _ Δ 6 A2.DtorWitness.prog_ok A2.DtorWitness.prog_codes
    (fun _ h => by cases h) GlobsOK.empty ht rfl A2.ArcDtorWitness.mainV_codes (by decide)

/-- Agora #790, the witnesses (`A2.ArcPanicWitness`): an `Arc` of a destructor
    value whose destructor panics, its last share dropped by a panic's
    unwinding, caught by a destructor frame with no `recover` (`main1`), by
    a `recover` (`main2`), or by a destructor frame inside a `recover`
    (`main3`), on one thread.  The claim covers all three: safe, race-free
    and leak-free on every interleaving.  (As for `arcDtor_claim`, the thread
    whose unwinding step dropped the last share reaps the orphan before its
    next step, with the same `Step.reap` at its redex, inside the catching
    frame, A2's `Settle` on the configuration (`CSettle`); on A2's `Steps`,
    `A2.ArcPanicWitness.main1_unwind`, `main2_unwind`, `main3_unwind`.) -/
theorem arcPanic_claim :
    (MemorySafe A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main1 7) ∧
      RaceFree A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main1 7) ∧
      NoLeak A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main1 7)) ∧
    (MemorySafe A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main2 1) ∧
      RaceFree A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main2 1) ∧
      NoLeak A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main2 1)) ∧
    (MemorySafe A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main3 1) ∧
      RaceFree A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main3 1) ∧
      NoLeak A2.ArcPanicWitness.P (fun _ => false) (Cfg.start Globs.empty A2.ArcPanicWitness.main3 1)) := by
  obtain ⟨Δ1, ht1⟩ := A2.ArcPanicWitness.main1_typed
  obtain ⟨Δ2, ht2⟩ := A2.ArcPanicWitness.main2_typed
  obtain ⟨Δ3, ht3⟩ := A2.ArcPanicWitness.main3_typed
  exact ⟨claim _ _ Globs.empty _ Δ1 7 A2.ArcPanicWitness.prog_ok A2.ArcPanicWitness.prog_codes
      (fun _ h => by cases h) GlobsOK.empty ht1 rfl A2.ArcPanicWitness.main1_codes (by decide),
    claim _ _ Globs.empty _ Δ2 1 A2.ArcPanicWitness.prog_ok A2.ArcPanicWitness.prog_codes
      (fun _ h => by cases h) GlobsOK.empty ht2 rfl A2.ArcPanicWitness.main2_codes (by decide),
    claim _ _ Globs.empty _ Δ3 1 A2.ArcPanicWitness.prog_ok A2.ArcPanicWitness.prog_codes
      (fun _ h => by cases h) GlobsOK.empty ht3 rfl A2.ArcPanicWitness.main3_codes (by decide)⟩

end A3

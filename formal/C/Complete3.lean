import C.Complete
import C.Cert3

/-! C15 for threaded programs (AGORA-1035): A3's claims over every completion
of a program with assumed functions. Apart from `C/Complete.lean` so that a
single-threaded conditional certificate loads no A3 (AGORA-1040). -/

namespace C

open A2

/-! ### Threaded programs (A3): conditional certificates (AGORA-1035) -/

theorem SpawnOK.complete {A : List Nat} {P P' : Prog} {spawn : Nat → Bool}
    (hc : Completes A P P') (h : A3.SpawnOK P spawn) : A3.SpawnOK P' spawn := by
  intro f hf
  obtain ⟨fn, hfn, hr, hp⟩ := h f hf
  obtain ⟨fn', hfn', hs, -⟩ := hc.fn_at hfn
  exact ⟨fn', hfn', hs.resTy ▸ hr, hs.params ▸ hp⟩

/-- The assumed functions of a threaded completion are well-typed, keep
    their code invariant, and read no module global (AGORA-1035). -/
def AssumedOK3 (A : List Nat) (P' : Prog) : Prop :=
  ∀ i ∈ A, ∃ fn, P'[i]? = some fn ∧ FnOK P' fn ∧ fn.body.codesOK P' ∧
    fn.body.globsAt (A3.declTy [])

theorem AssumedOK3.toAssumedOK {A : List Nat} {P' : Prog} (h : AssumedOK3 A P') :
    AssumedOK A P' :=
  fun i hi => let ⟨fn, hf, hok, hc, _⟩ := h i hi; ⟨fn, hf, hok, hc⟩

/-- The checker's whole verdict on a threaded program `P` with spawned
    functions `sp`, assumed functions `A`, and entry statement `s` over `nv`
    slots, with no module global (AGORA-1035). -/
def certOK3BA (P : Prog) (sp A : List Nat) (s : Stmt) (nv : Nat) : Bool :=
  certOK2BA P A s nv && spawnOKB P sp && progGlobsB P (A3.declTy []) &&
    stmtGlobsB (A3.declTy []) s

theorem certOK3BA_claim {P P' : Prog} {sp A : List Nat} {s : Stmt} {nv : Nat}
    (h : certOK3BA P sp A s nv = true) (hc : Completes A P P') (ha : AssumedOK3 A P') :
    A3.MemorySafe P' (fun f => decide (f ∈ sp)) (A3.Cfg.init s nv) ∧
    A3.RaceFree P' (fun f => decide (f ∈ sp)) (A3.Cfg.init s nv) ∧
    A3.NoLeak P' (fun f => decide (f ∈ sp)) (A3.Cfg.init s nv) := by
  simp only [certOK3BA, Bool.and_eq_true] at h
  obtain ⟨⟨⟨h2, hsp⟩, hpg⟩, hsg⟩ := h
  obtain ⟨hok, hcodes, ⟨Δ, ht⟩, hs, hsc, hv⟩ := certOK2BA_typed h2 hc ha.toAssumedOK
  have hSp' : A3.SpawnOK P' (fun f => decide (f ∈ sp)) :=
    SpawnOK.complete hc (spawnOKB_sound hsp)
  have hD' : A3.DeclsOK P' [] := declsOKB_sound (D := []) rfl
  have hPG' : ProgGlobs P' (A3.declTy []) := by
    intro fn hfn
    obtain ⟨i, hlt, hget⟩ := List.mem_iff_getElem.mp hfn
    have hi : P'[i]? = some fn := by rw [List.getElem?_eq_getElem hlt, hget]
    by_cases hA : i ∈ A
    · obtain ⟨fn', hf', _, _, hg'⟩ := ha i hA
      rw [hi] at hf'; cases hf'; exact hg'
    · have hk := hc.keep i hA
      rw [hi] at hk
      exact progGlobsB_sound hpg fn (List.mem_of_getElem? hk.symm)
  obtain ⟨-, hrun⟩ := A3.claim_made_full P' _ [] s Δ nv hok hcodes hSp' hD' hPG'
    ht hs hsc (stmtGlobsB_sound hsg) hv
  obtain ⟨hms, hrf, hnl, -, -⟩ := hrun A3.Globs.empty A3.Made.nil
  exact ⟨hms, hrf, hnl⟩

/-- `M.safe`, conditional for a threaded program (AGORA-1035). -/
theorem cert3_safe_cond {P : Prog} {sp A : List Nat} {s : Stmt} {nv : Nat}
    (h : certOK3BA P sp A s nv = true) :
    ∀ P', Completes A P P' → AssumedOK3 A P' →
      ∀ C, A3.Reach P' (fun f => decide (f ∈ sp)) (A3.Cfg.init s nv) C →
        ∀ (i : Nat) (t : A3.Thread), C.ths[i]? = some t → ¬ Stuck P' (C.view t) t.s :=
  fun _ hc ha => (certOK3BA_claim h hc ha).1

/-- `M.race`, conditional for a threaded program (AGORA-1035). -/
theorem cert3_race_cond {P : Prog} {sp A : List Nat} {s : Stmt} {nv : Nat}
    (h : certOK3BA P sp A s nv = true) :
    ∀ P', Completes A P P' → AssumedOK3 A P' →
      ∀ C, A3.Reach P' (fun f => decide (f ∈ sp)) (A3.Cfg.init s nv) C → ¬ A3.Race P' C :=
  fun _ hc ha => (certOK3BA_claim h hc ha).2.1

/-- `M.leak`, conditional for a threaded program (AGORA-1035). -/
theorem cert3_leak_cond {P : Prog} {sp A : List Nat} {s : Stmt} {nv : Nat}
    (h : certOK3BA P sp A s nv = true) :
    ∀ P', Completes A P P' → AssumedOK3 A P' →
      ∀ C, A3.Reach P' (fun f => decide (f ∈ sp)) (A3.Cfg.init s nv) C →
        (∀ t ∈ C.ths, t.s = .skip) → ∀ i, C.alloc i = false :=
  fun _ hc ha => A3.NoLeak.empty (A3.Cfg.init_start s nv ▸ (certOK3BA_claim h hc ha).2.2)

end C

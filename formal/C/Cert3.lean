module

public import C.Cert
public import C.A3Prog

@[expose] public section

/-!
# C14: a threaded program's certificate claims (AGORA-1020)

A program that spawns threads is certified against A3, not A2: A2's
semantics has no threads (a spawn would read as a call). `certOK3B P sp s nv`
is the checker's whole verdict on such a program: A2's typing of every
function and of the entry (`certOK2B`), and A3's conditions on the program
as a whole: the spawned functions `sp` (`spawnOKB`), and no module global
(`D = []`: their reads, `progGlobsB` / `stmtGlobsB`, are of none). One
boolean, so a certificate discharges it with one `decide`, and gets A3's
claim for the program run from its entry: on every interleaving of its
threads, no thread ever gets stuck (`cert3_safe`), no two race
(`cert3_race`), and once every thread has finished nothing is allocated
(`cert3_leak`).

The statements use A3's semantics only (`Reach`, `Stuck`, `Race`,
`Cfg.init`, `Cfg.alloc`); the checker is how they are proved.
-/

namespace C

open A2 A3

/-- The checker's whole verdict on program `P` with spawned functions `sp`
    and entry statement `s` over `nv` slots, with no module global. -/
def certOK3B (P : Prog) (sp : List Nat) (s : Stmt) (nv : Nat) : Bool :=
  certOK2B P s nv && spawnOKB P sp && progGlobsB P (declTy []) && stmtGlobsB (declTy []) s

theorem certOK3B_claim {P : Prog} {sp : List Nat} {s : Stmt} {nv : Nat} (h : certOK3B P sp s nv = true) :
    MemorySafe P (fun f => decide (f ∈ sp)) (Cfg.init s nv) ∧
    RaceFree P (fun f => decide (f ∈ sp)) (Cfg.init s nv) ∧
    NoLeak P (fun f => decide (f ∈ sp)) (Cfg.init s nv) := by
  simp only [certOK3B, Bool.and_eq_true] at h
  obtain ⟨⟨⟨h2, hsp⟩, hpg⟩, hsg⟩ := h
  obtain ⟨hP, ⟨Δ, hc⟩, hsc, hs, hv⟩ := certOK2B_parts h2
  have hD : declsOKB P [] = true := rfl
  obtain ⟨-, hrun⟩ := checked_claim_made_full hP hsp hD hpg hc hsc hsg hs hv
  obtain ⟨hms, hrf, hnl, -, -⟩ := hrun Globs.empty Made.nil
  exact ⟨hms, hrf, hnl⟩

/-- `M.safe` for a threaded program: on every interleaving, no thread of
    any reachable configuration is stuck. -/
theorem cert3_safe {P : Prog} {sp : List Nat} {s : Stmt} {nv : Nat} (h : certOK3B P sp s nv = true) :
    ∀ C, Reach P (fun f => decide (f ∈ sp)) (Cfg.init s nv) C →
      ∀ (i : Nat) (t : Thread), C.ths[i]? = some t → ¬ Stuck P (C.view t) t.s :=
  (certOK3B_claim h).1

/-- `M.race`: no reachable configuration has a data race. -/
theorem cert3_race {P : Prog} {sp : List Nat} {s : Stmt} {nv : Nat} (h : certOK3B P sp s nv = true) :
    ∀ C, Reach P (fun f => decide (f ∈ sp)) (Cfg.init s nv) C → ¬ Race P C :=
  (certOK3B_claim h).2.1

/-- `M.leak` for a threaded program: once every thread has finished,
    nothing is allocated. -/
theorem cert3_leak {P : Prog} {sp : List Nat} {s : Stmt} {nv : Nat} (h : certOK3B P sp s nv = true) :
    ∀ C, Reach P (fun f => decide (f ∈ sp)) (Cfg.init s nv) C → (∀ t ∈ C.ths, t.s = .skip) →
      ∀ i, C.alloc i = false :=
  NoLeak.empty (Cfg.init_start s nv ▸ (certOK3B_claim h).2.2)

end C

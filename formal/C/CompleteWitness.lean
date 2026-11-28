module

public import C.Complete3

@[expose] public section

/-! C15's witnesses: a program with an assumed function whose checker
verdict, completion and claims hold, single-threaded and threaded. Apart
from `C/Complete.lean` and `C/Complete3.lean` so that a certificate loads
no witness program (AGORA-1013, AGORA-1040). -/

namespace C

open A2

/-! ### A witness: the hypotheses can hold

`@ seven → i { ^ 7 }  @ main → i { ^ ( seven ) }`, with `seven` (index 0)
assumed: `P` holds its stub, the checker accepts, and the real program
(`seven`'s translated body) is a completion in which `seven` is well-typed.
So the conditional claims are not vacuous: the real program is one of the
programs they speak about. -/

/-- `seven`, as the translation makes it. -/
def condWitnessSeven : Fn :=
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := (.block (.seq (.assign 0 (.expr .any)) (.exit 0))), nvars := 2 }

/-- `seven`'s stub: its signature, no callees, no change through a borrow. -/
def condWitnessStub : Fn := { condWitnessSeven with body := .seq .skip .panic, nvars := 0 }

def condWitnessMain : Fn :=
  { params := [], resTy := .int, resOwn := false, lends := [], rholds := [],
    outHolds := [], body := (.block (.seq (.letcall 1 0 [] (.assign 0 (.expr .any))) (.exit 0))), nvars := 3 }

def condWitnessP : Prog := [condWitnessStub, condWitnessMain]
def condWitnessReal : Prog := [condWitnessSeven, condWitnessMain]
def condWitnessEntry : Stmt := .letcall 0 1 [] .skip

theorem cond_witness_ok : certOK2BA condWitnessP [0] condWitnessEntry 1 = true := by decide +kernel

/-- An assumed index past the program's end is refused: it could never be
    completed. -/
theorem cond_witness_bad_index : certOK2BA condWitnessP [0, 2] condWitnessEntry 1 = false := by
  decide +kernel

theorem cond_witness_completes : Completes [0] condWitnessP condWitnessReal where
  len := rfl
  keep := by
    intro i hi
    match i with
    | 0 => exact absurd (List.mem_singleton_self 0) hi
    | 1 => rfl
    | _ + 2 => rfl
  stub := by
    intro i hi
    rw [List.mem_singleton] at hi; subst hi
    exact ⟨condWitnessStub, condWitnessSeven, rfl, rfl, rfl, ⟨fun _ => by simp [Stmt.calls, condWitnessStub,
      condWitnessSeven], rfl⟩, .skip, rfl⟩

theorem cond_witness_assumed : AssumedOK [0] condWitnessReal := by
  intro i hi
  rw [List.mem_singleton] at hi; subst hi
  refine ⟨condWitnessSeven, rfl, fnOK2B_sound (f := 0) rfl (by decide +kernel),
    stmtCodesB_sound (by decide +kernel)⟩

/-- The real program never gets stuck, by the conditional claim. -/
theorem cond_witness_safe :
    ∀ m' s', Steps condWitnessReal (emptyMem 1) condWitnessEntry (.ok m' s') → ¬ Stuck condWitnessReal m' s' :=
  cert_safe_cond cond_witness_ok _ cond_witness_completes cond_witness_assumed

/-- Witness for A3 conditional certificates: `seven` (index 0) is both spawned
    and assumed; `certOK3BA` accepts and the conditional claims apply to the
    real program. -/
theorem cond3_witness_ok : certOK3BA condWitnessP [0] [0] condWitnessEntry 1 = true := by
  decide +kernel

theorem cond3_witness_assumed : AssumedOK3 [0] condWitnessReal := by
  intro i hi
  rw [List.mem_singleton] at hi; subst hi
  refine ⟨condWitnessSeven, rfl, fnOK2B_sound (f := 0) rfl (by decide +kernel),
    stmtCodesB_sound (by decide +kernel), stmtGlobsB_sound (by decide +kernel)⟩

theorem cond3_witness_race :
    ∀ C, A3.Reach condWitnessReal (fun f => decide (f ∈ [0])) (A3.Cfg.init condWitnessEntry 1) C →
      ¬ A3.Race condWitnessReal C :=
  cert3_race_cond cond3_witness_ok _ cond_witness_completes cond3_witness_assumed

end C

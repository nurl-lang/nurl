module

public import A2.Typing

@[expose] public section

/-! # A call is handed no argument that views its own storage, where the callee moves or changes it (AGORA-606, AGORA-563)

    : A { ( Vec String ) arena ( Vec s ) idx }
    @ bad inout A p → v { ( vec_clear . p arena )  ( nurl_println ( vec_at . p idx 0 ) ) }
    -- `. a idx` holds views of the Strings of `. a arena`: ( bad a )

Inside `bad` the two fields of its parameter are unrelated names, so the read
after the clear would be of freed memory.  `CallT` refuses the call: an
argument the callee moves (`sink`) or may change (`inout`) is not a root of
its own memory dependencies, and a `sink` one of any of its dependencies.  A
value one field of which views another (an `outHolds` of its own path, as a
callee leaves it; rules/t600.md) is such a root.  nurlc's checks of the shape
(`__bck_sva_hit`, `__bck_sva_sink`, `__bck_slit_check`; rules/t606.md,
rules/t563.md) are brought into line with these two lemmas, which pin the
premise they rest on.  A plain (`inp`) parameter is never changed: what a
borrowed parameter reaches is frozen inside the call, so a callee that clears
its field is not typed at all. -/

namespace A2

/-- An argument at a parameter the callee moves or may change, that is a root
    of its own memory dependencies (a value viewing its own storage), admits
    no `CallT`. -/
theorem CallT.not_self_view {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var}
    {E : Entry} {Γ' : Ctx} {fn : Fn} {i : Nat} {Ea : Entry}
    (hf : P[f]? = some fn) (hi : i < fn.params.length)
    (hm : fn.params[i].1.moves = true)
    (hE : Γ (args.getD i 0) = some Ea)
    (hself : args.getD i 0 ∈ roots (memDeps Ea.vdeps)) :
    ¬ CallT P Γ F f args E Γ' := by
  rintro ⟨fn', hf', _, hargs, _⟩
  rw [hf] at hf'
  cases hf'
  obtain ⟨Ea', hEa', _, _, hmv, _⟩ := hargs i hi
  rw [hE] at hEa'
  cases hEa'
  exact (hmv hm).2.1 hself

/-- …and one at a `sink` parameter that is a root of any of its dependencies,
    a view of its own storage of any kind. -/
theorem CallT.not_self_dep_sink {P : Prog} {Γ : Ctx} {F : List Var} {f : Nat} {args : List Var}
    {E : Entry} {Γ' : Ctx} {fn : Fn} {i : Nat} {Ea : Entry}
    (hf : P[f]? = some fn) (hi : i < fn.params.length)
    (hs : fn.params[i].1 = .sink)
    (hE : Γ (args.getD i 0) = some Ea)
    (hself : args.getD i 0 ∈ roots Ea.vdeps) :
    ¬ CallT P Γ F f args E Γ' := by
  rintro ⟨fn', hf', _, hargs, _⟩
  rw [hf] at hf'
  cases hf'
  obtain ⟨Ea', hEa', _, _, hmv, _⟩ := hargs i hi
  rw [hE] at hEa'
  cases hEa'
  have hm : fn.params[i].1.moves = true := by rw [hs]; rfl
  exact (hmv hm).2.2.1 hs hself

end A2

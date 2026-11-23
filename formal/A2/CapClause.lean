import A2.KillVarsStep

namespace A2

/-! AGORA-937 B2 (AGORA-963): the closure-capture clause. A held anchor's
root (not lent out) is captured by no package in the store but read-only,
so a call through a package never hands it to an `inout` parameter of the
code (`CapInout`), and a step names it as no new killable name. By
claude-expert. -/

theorem capPos {zs : List Var} {cs : List (Var × PMode × Ty)} {n : Nat} {pre : List (PMode × Ty)}
    {i : Nat} {v : Var} {pm : PMode × Ty}
    (hlen : pre.length = zs.length) (hi : zs.length + 1 ≤ i)
    (hv : (n :: zs ++ cs.map (·.1))[i]? = some v)
    (hp : (pm :: pre ++ cs.map (·.2))[i]? = some (PMode.inout b, t)) :
    ∃ q ∈ cs, q.1 = v ∧ q.2.1 = PMode.inout b := by
  obtain ⟨k, rfl⟩ : ∃ k, i = k + 1 := ⟨i - 1, by omega⟩
  have hk : zs.length ≤ k := by omega
  have hk' : pre.length ≤ k := by omega
  simp only [List.cons_append, List.getElem?_cons_succ] at hv hp
  rw [List.getElem?_append_right hk, List.getElem?_map] at hv
  rw [List.getElem?_append_right hk', List.getElem?_map, hlen] at hp
  cases hq : cs[k - zs.length]? with
  | none => rw [hq] at hv; cases hv
  | some q =>
    rw [hq] at hv hp
    simp only [Option.map_some, Option.some.injEq] at hv hp
    exact ⟨q, List.mem_of_getElem? hq, hv, by rw [hp]⟩

theorem CapInout.not_held {P : Prog} {m : Mem} {Γ : Ctx} {F : List Var} {s : Stmt}
    (hcl : HeldCapsInp m Γ F s) (hcodes : MemCodes P m)
    {p : Var} {E : Entry} {d : Dep} (hp : Γ p = some E) (hm : E.mode = .rootb) (hps : p ∉ s.spine)
    (hd : d ∈ E.vdeps) (hb : d.kind.bound = .none) (hh : HeldAnch E d) (hF : d.root ∉ F) :
    ¬ CapInout P m d.root := by
  rintro ⟨c, o, fs, te, ms, env, cs, j, f, fn, zs, i, b, t, hc, hj, hf, hl, hi, hai, hpi⟩
  have hcode := hcodes.1 c o _ fs te ms env cs hc (Sub.refl _)
  obtain ⟨hlen, himpl⟩ := hcode
  have hjl : j < ms.length := by
    rw [← hlen]
    rcases Nat.lt_or_ge j fs.length with h | h
    · exact h
    · rw [List.getElem?_eq_none h] at hj; cases hj
  obtain ⟨fn', sig, hf', hsig, hpar, -⟩ := himpl j f ms[j] hj (List.getElem?_eq_getElem hjl)
  rw [hf] at hf'; cases hf'
  rw [hpar] at hpi hl
  have hlen' : sig.params.tail.length = zs.length := by
    simp only [List.length_cons, List.length_append, List.length_map] at hl; omega
  obtain ⟨q, hq, hq1, hq2⟩ := capPos hlen' hi hai hpi
  have := (hcl p E hp hm hps d hd hb hh hF).1 c o _ hc fs te ms env cs (Sub.refl _) q hq hq1
  rw [hq2] at this; cases this

theorem Step.held_not_killVars {P : Prog} {m m' : Mem} {Γ : Ctx} {F : List Var} {s s' : Stmt}
    (hstep : Step P m s (.ok m' s')) (hcl : HeldCapsInp m Γ F s) (hcodes : MemCodes P m)
    {p : Var} {E : Entry} {d : Dep} (hp : Γ p = some E) (hm : E.mode = .rootb) (hps : p ∉ s.spine)
    (hd : d ∈ E.vdeps) (hb : d.kind.bound = .none) (hh : HeldAnch E d) (hF : d.root ∉ F)
    (hkv : d.root ∉ s.killVars) (hlt : d.root < m.nv) : d.root ∉ s'.killVars := by
  intro hin
  rcases hstep.killVars_sub m' s' rfl d.root hin with h | h | h
  · exact hkv h
  · exact absurd h (Nat.not_le.mpr hlt)
  · exact CapInout.not_held hcl hcodes hp hm hps hd hb hh hF h

end A2

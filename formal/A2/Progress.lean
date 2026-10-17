import A2.Preservation

/-! A2 — progress: a well-typed configuration has finished, or it steps (or
panics, which is a defined way to stop). -/

namespace A2

theorem eval_exists {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {e : Expr} (he : ExprT Γ e) :
    ∃ n, Eval m e n := by
  induction he with
  | lit => exact ⟨_, Eval.lit⟩
  | var hx hl ht =>
    rename_i x E
    have hos : E.mode.ownSlot = false := by
      cases h : E.mode.ownSlot with
      | false => rfl
      | true =>
        obtain ⟨_, _, _, _, hown, _⟩ := hi.slot x E hx
        obtain ⟨⟨t, h'⟩, _⟩ := hown h
        rw [ht] at h'; cases h'
    obtain ⟨v, hv, hok⟩ := hi.bor_val hx hl hos
    rw [ht] at hok
    obtain ⟨n, rfl⟩ := hok
    exact ⟨n, Eval.var hv⟩
  | add _ _ iha ihb =>
    obtain ⟨p, hp⟩ := iha; obtain ⟨q, hq⟩ := ihb; exact ⟨_, Eval.add hp hq⟩
  | lt _ _ iha ihb =>
    obtain ⟨p, hp⟩ := iha; obtain ⟨q, hq⟩ := ihb; exact ⟨_, Eval.lt hp hq⟩
  | len hx hl ht =>
    obtain ⟨c, d, es, hvec, _⟩ := hi.vec_node hx hl ht
    exact ⟨_, Eval.len hvec⟩
  | slen hx hl ht =>
    obtain ⟨d, o, l, _, _, hs, _⟩ := hi.slice_node hx hl ht
    exact ⟨_, Eval.slen hs⟩

theorem frees_owned {m : Mem} (hh : HeapOK m) {x : Var} {τ : Ty} {t : Val}
    (hx : m.st x = some ⟨true, some t⟩) (hw : WFv τ t) : ∃ a', Frees m.alloc t a' :=
  frees_exists hw m.alloc (hh.nodup x t hx) (fun i hi => (hh.alloc x t hx i hi).1)

theorem dropSlot_exists {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {x : Var} {E : Entry}
    (hx : Γ x = some E) : ∃ sl a', m.st x = some sl ∧ DropSlot m.alloc sl a' := by
  obtain ⟨sl, hsl, _, hso, hown, _⟩ := hi.slot x E hx
  obtain ⟨o, val⟩ := sl
  cases o with
  | false => exact ⟨_, m.alloc, hsl, DropSlot.borrowed⟩
  | true =>
    cases val with
    | none => exact ⟨_, m.alloc, hsl, DropSlot.moved⟩
    | some t =>
      have hos : E.mode.ownSlot = true := by simp at hso; exact hso
      obtain ⟨_, hwf, _⟩ := hown hos
      obtain ⟨a', ha⟩ := frees_owned hi.heap hsl (hwf t rfl)
      exact ⟨_, a', hsl, DropSlot.owned ha⟩

theorem evalR_exists {m : Mem} {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hi : MInv m Γ)
    (hr : RhsT Γ F r E Γ1) : ∃ res, EvalR m r res := by
  cases hr with
  | expr he =>
    obtain ⟨n, hn⟩ := eval_exists hi he; exact ⟨_, EvalR.expr hn⟩
  | new _ => exact ⟨_, EvalR.new⟩
  | moveOwn hy hl hm _ =>
    obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    exact ⟨_, EvalR.moveOwn hT⟩
  | copyRoot hy hl hm =>
    obtain ⟨v, hv, _⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    exact ⟨_, EvalR.copy hv⟩
  | copyBor hy hl hm =>
    obtain ⟨v, hv, _⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    exact ⟨_, EvalR.copy hv⟩
  | borrow hy hl ht =>
    obtain ⟨c, d, es, ⟨_, _, hvec⟩, _⟩ := hi.vec_node hy hl ht
    rcases hvec with h | ⟨h, _⟩
    · exact ⟨_, EvalR.borrowOwn h⟩
    · exact ⟨_, EvalR.borrowBor h⟩
  | «at» hy hl ht hi' =>
    obtain ⟨c, d, es, hvec, _⟩ := hi.vec_node hy hl ht
    obtain ⟨n, hn⟩ := eval_exists hi hi'
    by_cases hlt : n < es.length
    · exact ⟨_, EvalR.at hlt hvec hn⟩
    · exact ⟨_, EvalR.atOOB hvec hn (by omega)⟩
  | view hy hl ht _ =>
    obtain ⟨c, d, es, hvec, _⟩ := hi.vec_node hy hl ht
    exact ⟨_, EvalR.view hvec⟩
  | sat hy hl ht hi' =>
    obtain ⟨d, o, l, c, es, hs, hda, had, hlen, _⟩ := hi.slice_node hy hl ht
    obtain ⟨n, hn⟩ := eval_exists hi hi'
    by_cases hlt : n < l
    · exact ⟨_, EvalR.sat (by omega) hs hn hlt had hda⟩
    · exact ⟨_, EvalR.satOOB hs hn (by omega)⟩
  | @pop y E' t hy hl ht hcan _ =>
    have hm : E'.mode = .own := by
      rcases hcan with h | ⟨b, h, _⟩
      · exact h
      · exact absurd h (hi.noInout y E' b hy)
    obtain ⟨c, d, es, ⟨hac, had, hvec⟩, _⟩ := hi.vec_node hy hl ht
    rcases hvec with h | ⟨h, _⟩
    · rcases List.eq_nil_or_concat es with rfl | ⟨es', e, rfl⟩
      · exact ⟨_, EvalR.popEmpty h⟩
      · rw [List.concat_eq_append] at h; exact ⟨_, EvalR.pop h hac had⟩
    · obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
      rw [hT] at h; cases h

/-- Progress for every statement but a call, given the call case. -/
theorem progress {P : Prog}
    (hcall : ∀ {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {k : Stmt}
      {E : Entry} {Γ1 : Ctx} {m : Mem}, Γ x = none → CallT P Γ F f args E Γ1 → MInv m Γ →
      ∃ r, Step P m (.letcall x f args k) r)
    {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (ht : StmtT P Γ F s Δ) :
    ∀ {m : Mem}, Inv m Γ F s → s = .skip ∨ ∃ r, Step P m s r := by
  induction ht with
  | skip => exact fun _ => Or.inl rfl
  | sub hw _ _ ih => exact fun hi => ih (hi.weaker hw)
  | seq _ _ _ iha _ =>
    intro m hi
    rcases iha (hi.respine rfl (fun v hv => hi.nvS v (by simp [Stmt.vars, hv]))) with rfl | ⟨r, hr⟩
    · exact Or.inr ⟨_, Step.seqSkip⟩
    · cases r with
      | ok m' a' => exact Or.inr ⟨_, Step.seqL hr⟩
      | panic => exact Or.inr ⟨_, Step.seqP hr⟩
  | @letv Γ Γ1 Δ F x r k E _ hx _ hr _ _ =>
    intro m hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    obtain ⟨res, hres⟩ := evalR_exists hi.toMInv hr
    cases res with
    | ok v o m1 => exact Or.inr ⟨_, Step.letv hmx hres⟩
    | panic => exact Or.inr ⟨_, Step.letvP hres⟩
  | @letcall Γ Γ1 Δ F x f args k E _ hx _ hc _ _ =>
    intro m hi
    exact Or.inr (hcall (k := k) hx hc hi.toMInv)
  | @scope Γ Δ1 F x k hxE _ _ ih =>
    intro m hi
    obtain ⟨Ex, hx, hnrb⟩ := hxE
    have hi0 : Inv m Γ F k :=
      { toMInv := hi.toMInv
        nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
        nvF := hi.nvF
        anch := fun p E hp hm hps => hi.anch p E hp hm (by
          simp only [Stmt.spine, List.mem_cons, not_or]
          refine ⟨fun h => ?_, hps⟩
          subst h; rw [hx] at hp; cases hp; exact hnrb hm)
        spineNd := by
          have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.2
        spineDom := fun v hv => hi.spineDom v (by simp [Stmt.spine, hv]) }
    rcases ih hi0 with rfl | ⟨r, hr⟩
    · obtain ⟨sl, a', hsl, hd⟩ := dropSlot_exists hi.toMInv hx
      exact Or.inr ⟨_, Step.scopeSkip hsl hd⟩
    · cases r with
      | ok m' k' => exact Or.inr ⟨_, Step.scopeIn hr⟩
      | panic => exact Or.inr ⟨_, Step.scopeP hr⟩
  | @rbind Γ Δ1 F p k Ep hp hm hl hroots _ _ ih =>
    intro m hi
    have hi0 : Inv m Γ F k :=
      { toMInv := hi.toMInv
        nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
        nvF := hi.nvF
        anch := fun q E hq hmq hqs => by
          by_cases hqp : q = p
          · subst hqp; rw [hp] at hq; cases hq; exact hroots
          · exact hi.anch q E hq hmq (by simp [Stmt.spine, hqp, hqs])
        spineNd := by
          have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.2
        spineDom := fun v hv => hi.spineDom v (by simp [Stmt.spine, hv]) }
    rcases ih hi0 with rfl | ⟨r, hr⟩
    · obtain ⟨sl, hsl, _⟩ := hi.slot p Ep hp
      exact Or.inr ⟨_, Step.rbindSkip hsl⟩
    · cases r with
      | ok m' k' => exact Or.inr ⟨_, Step.rbindIn hr⟩
      | panic => exact Or.inr ⟨_, Step.rbindP hr⟩
  | frozen _ ih =>
    intro m hi
    have hi0 := hi
    rcases ih { toMInv := hi.toMInv
                nvS := fun v hv => hi.nvS v (by simp [Stmt.vars, hv])
                nvF := fun v hv => by
                  rcases List.mem_append.mp hv with hv | hv
                  · exact hi.nvF v hv
                  · exact hi.nvS v (by simp [Stmt.vars, hv])
                anch := fun p E hp hm hps r hr => List.mem_append_left _ (hi.anch p E hp hm hps r hr)
                spineNd := hi.spineNd
                spineDom := hi.spineDom } with h | ⟨r, hr⟩
    · subst h; exact Or.inr ⟨_, Step.frozenSkip⟩
    · cases r with
      | ok m' k' => exact Or.inr ⟨_, Step.frozenIn hr⟩
      | panic => exact Or.inr ⟨_, Step.frozenP hr⟩
  | @assign Γ Γ1 F x r Ex E hx _ _ hr _ _ _ =>
    intro m hi
    obtain ⟨res, hres⟩ := evalR_exists hi.toMInv hr
    cases res with
    | panic => exact Or.inr ⟨_, Step.assignP hres⟩
    | ok v o m1 =>
      obtain ⟨post, _⟩ := rhs_pres hi.toMInv (hi.leafAnch rfl) hr hres
      have hx1 : (Γ1 x).isSome := by rw [post.cdom, hx]; rfl
      obtain ⟨Ex1, hEx1⟩ := Option.isSome_iff_exists.mp hx1
      obtain ⟨sl, a', hsl, hd⟩ := dropSlot_exists post.inv hEx1
      exact Or.inr ⟨_, Step.assign (by rw [← hi.dom x, hx]; rfl) hres hsl hd⟩
  | ite _ _ hc _ _ _ _ =>
    intro m hi
    obtain ⟨n, hn⟩ := eval_exists hi.toMInv hc
    by_cases h0 : n = 0
    · subst h0; exact Or.inr ⟨_, Step.iteF hn⟩
    · exact Or.inr ⟨_, Step.iteT hn h0⟩
  | «while» _ _ _ _ => exact fun _ => Or.inr ⟨_, Step.while⟩
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx hl hty hcan hxF hy hly htyy hyx hpa _ _ _ =>
    intro m hi
    have hmx : Ex.mode = .own := by
      rcases hcan with h | ⟨b, h, _⟩
      · exact h
      · exact absurd h (hi.noInout x Ex b hx)
    obtain ⟨c, d, es, ⟨hac, had, hvec⟩, _⟩ := hi.vec_node hx hl hty
    have hT : m.st x = some ⟨true, some (.node t c d es)⟩ := by
      rcases hvec with h | ⟨h, _⟩
      · exact h
      · obtain ⟨T, hT, _⟩ := hi.own_val hx hl (by rw [hmx]; rfl); rw [hT] at h; cases h
    -- the value to push
    have htake : ∃ v m1, TakeVal m y v m1 ∧ m1.st x = m.st x ∧ m1.alloc = m.alloc := by
      rcases hi.mode_cases hy with h | h | h
      · obtain ⟨T, hT', _⟩ := hi.own_val hy hly (by rw [h]; rfl)
        exact ⟨T, _, TakeVal.own hT', by simp [upd_ne _ _ (Ne.symm hyx)], rfl⟩
      all_goals
        obtain ⟨v, hv, _⟩ := hi.bor_val hy hly (by rw [h]; rfl)
        exact ⟨v, m, TakeVal.bor hv, rfl, rfl⟩
    obtain ⟨v, m1, htk, hst, hal⟩ := htake
    exact Or.inr ⟨_, Step.push htk (by rw [hst]; exact hT) (by rw [hal]; exact hac)
      (by rw [hal]; exact had)⟩
  | @free Γ F x E t hx hl hm hty _ =>
    intro m hi
    obtain ⟨T, hT, hwf, _⟩ := hi.own_val hx hl (by rw [hm]; rfl)
    obtain ⟨a', ha⟩ := frees_owned hi.heap hT hwf
    exact Or.inr ⟨_, Step.free hT ha⟩

end A2

import A2.Preservation

/-! A2 — progress: a well-typed configuration has finished, or it steps (or
panics, which is a defined way to stop). -/

namespace A2

/-- A live enum binding holds an enum. -/
theorem sum_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {a b : Ty} (ht : E.ty = .sum a b) :
    ∃ v, (m.st y = some ⟨E.mode.ownSlot, some (.inl v)⟩) ∨ (m.st y = some ⟨E.mode.ownSlot, some (.inr v)⟩) := by
  rcases hi.mode_cases hy with hm | hm | hm
  · obtain ⟨T, hT, hw, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    rw [ht] at hw; rw [hm]
    cases hw with
    | inl _ => exact ⟨_, Or.inl hT⟩
    | inr _ => exact ⟨_, Or.inr hT⟩
  all_goals
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    rw [ht] at hok; rw [hm]
    rcases valOK_sum.mp hok with ⟨x, rfl, _⟩ | ⟨x, rfl, _⟩
    · exact ⟨_, Or.inl hv⟩
    · exact ⟨_, Or.inr hv⟩

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
        obtain ⟨h', _⟩ := hown h
        rw [ht] at h'; cases h'
    obtain ⟨v, hv, hok⟩ := hi.bor_val hx hl hos
    rw [ht] at hok
    obtain ⟨n, rfl⟩ := valOK_int.mp hok
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
  | isl hx hl ht =>
    obtain ⟨v, hv | hv⟩ := sum_slot hi hx hl ht
    · exact ⟨_, Eval.isl hv⟩
    · exact ⟨_, Eval.isr hv⟩

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

/-- A live binding has a value to hand on. -/
theorem takeVal_exists {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) : ∃ v m1, TakeVal m y v m1 := by
  rcases hi.mode_cases hy with hm | hm | hm
  · obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    exact ⟨T, _, TakeVal.own hT⟩
  all_goals
    obtain ⟨v, hv, _⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    exact ⟨v, m, TakeVal.bor hv⟩

/-- A live struct binding holds a struct. -/
theorem pair_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {a b : Ty} (ht : E.ty = .prod a b) :
    ∃ o v w, m.st y = some ⟨o, some (.pair v w)⟩ := by
  rcases hi.mode_cases hy with hm | hm | hm
  · obtain ⟨T, hT, hw, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    rw [ht] at hw; cases hw
    exact ⟨_, _, _, hT⟩
  all_goals
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    rw [ht] at hok; obtain ⟨x, z, rfl, _⟩ := valOK_prod.mp hok
    exact ⟨_, _, _, hv⟩

theorem evalR_exists {m : Mem} {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    (hr : RhsT Γ F r E Γ1) : ∃ res, EvalR m r res := by
  cases hr with
  | expr he =>
    obtain ⟨n, hn⟩ := eval_exists hi he; exact ⟨_, EvalR.expr hn⟩
  | new _ => exact ⟨_, EvalR.new⟩
  | moveOwn hy hl hm _ _ =>
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
  | @pair y z Ey Ez Γ1 Γ2 Dy Dz hy hly hpa1 hz hlz _ _ =>
    obtain ⟨v, m1, htk1⟩ := takeVal_exists hi hy hly
    obtain ⟨post1, _⟩ := push_take hi hanch hy hly rfl hpa1 htk1
    obtain ⟨w, m2, htk2⟩ := takeVal_exists post1.inv hz hlz
    exact ⟨_, EvalR.pair htk1 htk2⟩
  | fst hy hl ht =>
    obtain ⟨o, v, w, hv⟩ := pair_slot hi hy hl ht
    exact ⟨_, EvalR.fst hv⟩
  | snd hy hl ht =>
    obtain ⟨o, v, w, hv⟩ := pair_slot hi hy hl ht
    exact ⟨_, EvalR.snd hv⟩
  | inl hy hly _ _ =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly
    exact ⟨_, EvalR.inl htk⟩
  | inr hy hly _ _ =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly
    exact ⟨_, EvalR.inr htk⟩
  | pack hy hly _ _ _ =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly
    exact ⟨_, EvalR.pack htk⟩
  | getl hy hl ht =>
    obtain ⟨v, hv | hv⟩ := sum_slot hi hy hl ht
    · exact ⟨_, EvalR.getl hv⟩
    · exact ⟨_, EvalR.getlP hv⟩
  | getr hy hl ht =>
    obtain ⟨v, hv | hv⟩ := sum_slot hi hy hl ht
    · exact ⟨_, EvalR.getrP hv⟩
    · exact ⟨_, EvalR.getr hv⟩
  | takel hy hl hm ht _ _ =>
    obtain ⟨v, hv | hv⟩ := sum_slot hi hy hl ht <;> rw [hm] at hv
    · exact ⟨_, EvalR.takel hv⟩
    · exact ⟨_, EvalR.takelP hv⟩
  | taker hy hl hm ht _ _ =>
    obtain ⟨v, hv | hv⟩ := sum_slot hi hy hl ht <;> rw [hm] at hv
    · exact ⟨_, EvalR.takerP hv⟩
    · exact ⟨_, EvalR.taker hv⟩

/-- Progress for every statement but a call, given the call case. -/
theorem progress {P : Prog}
    (hcall : ∀ {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {k : Stmt}
      {E : Entry} {Γ1 : Ctx} {m : Mem}, Γ x = none → CallT P Γ F f args E Γ1 → MInv m Γ →
      ∃ r, Step P m (.letcall x f args k) r)
    (hclo : ∀ {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt}
      {Ec E : Entry} {ms : List Nat} {σ : Nat} {sig : Fn} {m : Mem},
      Γ x = none → x ∉ F → Γ c = some Ec → Ec.ty = .fn ms → ms[j]? = some σ → P[σ]? = some sig →
      sig.params.head? = some (.inp, .fn ms) → CallT P Γ F σ (c :: zs) E Γ1 →
      (∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z) →
      MemCodes P m → Inv m Γ F (.callc x c j zs k) → ∃ r, Step P m (.callc x c j zs k) r)
    {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (ht : StmtT P Γ F s Δ) :
    ∀ {m : Mem}, MemCodes P m → Inv m Γ F s → s = .skip ∨ ∃ r, Step P m s r := by
  induction ht with
  | skip => exact fun _ _ => Or.inl rfl
  | sub hw _ _ ih => exact fun hcd hi => ih hcd (hi.weaker hw)
  | seq _ _ _ iha _ =>
    intro m hcd hi
    rcases iha hcd hi.seqIn with rfl | ⟨r, hr⟩
    · exact Or.inr ⟨_, Step.seqSkip⟩
    · cases r with
      | ok m' a' => exact Or.inr ⟨_, Step.seqL hr⟩
      | panic => exact Or.inr ⟨_, Step.seqP hr⟩
  | @letv Γ Γ1 Δ F x r k E _ hx _ hr _ _ _ =>
    intro m hcd hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    obtain ⟨res, hres⟩ := evalR_exists hi.toMInv (hi.leafAnch rfl) hr
    cases res with
    | ok v o m1 => exact Or.inr ⟨_, Step.letv hmx hres⟩
    | panic => exact Or.inr ⟨_, Step.letvP hres⟩
  | @letcall Γ Γ1 Δ F x f args k E _ hx _ hc _ _ _ =>
    intro m hcd hi
    exact Or.inr (hcall (k := k) hx hc hi.toMInv)
  | @scope Γ Δ1 F x k hxE _ _ _ ih =>
    intro m hcd hi
    obtain ⟨Ex, hx, hnrb⟩ := hxE
    have hi0 : Inv m Γ F k := hi.scopeIn hx hnrb
    rcases ih hcd hi0 with rfl | ⟨r, hr⟩
    · obtain ⟨sl, a', hsl, hd⟩ := dropSlot_exists hi.toMInv hx
      exact Or.inr ⟨_, Step.scopeSkip hsl hd⟩
    · cases r with
      | ok m' k' => exact Or.inr ⟨_, Step.scopeIn hr⟩
      | panic m1 =>
        obtain ⟨hout, _, hh1, _⟩ := panic_unwind hr hi.heap hi.cover hi0.spineNd
        have hxs : x ∉ k.spine := by
          have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
        obtain ⟨sl, hsl, _, hso, hown, _⟩ := hi.slot x Ex hx
        have hsl1 : m1.st x = some sl := by rw [hout x hxs]; exact hsl
        obtain ⟨a', hd⟩ : ∃ a', DropSlot m1.alloc sl a' := by
          obtain ⟨o, val⟩ := sl
          cases o with
          | false => exact ⟨_, DropSlot.borrowed⟩
          | true =>
            cases val with
            | none => exact ⟨_, DropSlot.moved⟩
            | some t =>
              obtain ⟨_, hwf, _⟩ := hown (by simp at hso; exact hso)
              obtain ⟨a', ha⟩ := frees_owned hh1 hsl1 (hwf t rfl)
              exact ⟨a', DropSlot.owned ha⟩
        exact Or.inr ⟨_, Step.scopeP hr hsl1 hd⟩
  | @letd Γ Γ1 Δ F x f r k E _ _ hx _ hr _ _ _ _ _ _ =>
    intro m hcd hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    obtain ⟨res, hres⟩ := evalR_exists hi.toMInv (hi.leafAnch rfl) hr
    cases res with
    | ok v o m1 => exact Or.inr ⟨_, Step.letd hmx hres⟩
    | panic => exact Or.inr ⟨_, Step.letdP hres⟩
  | @scopeD Γ Δ1 F x f k hxE _ _ _ _ _ _ _ ih =>
    intro m hcd hi
    obtain ⟨Ex, hx, hmo, _, _⟩ := hxE
    have hnrb : Ex.mode ≠ .rootb := by rw [hmo]; simp
    have hiS : Inv m Γ F (.scope x k) := Inv.scopeD_iff.mp hi
    have hi0 : Inv m Γ F k := hiS.scopeIn hx hnrb
    -- `x` owns its slot: a value, or none once moved
    have hown : ∀ m' : Mem, m'.st x = m.st x → ∃ val, m'.st x = some ⟨true, val⟩ := by
      intro m' he
      obtain ⟨⟨o, val⟩, hsl, _, hso, _⟩ := hi.slot x Ex hx
      rw [hmo] at hso; simp [Mode.ownSlot] at hso; subst hso; exact ⟨val, by rw [he, hsl]⟩
    rcases ih hcd hi0 with rfl | ⟨r, hr⟩
    · obtain ⟨val, hsl⟩ := hown m rfl
      cases val with
      | none => exact Or.inr ⟨_, Step.scopeDMoved hsl⟩
      | some v => exact Or.inr ⟨_, Step.scopeDEnd hsl⟩
    · cases r with
      | ok m' k' => exact Or.inr ⟨_, Step.scopeDIn hr⟩
      | panic m1 =>
        obtain ⟨hout, _⟩ := panic_unwind hr hi.heap hi.cover hi0.spineNd
        have hxs : x ∉ k.spine := by
          have := hiS.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
        obtain ⟨val, hsl⟩ := hown m1 (hout x hxs)
        cases val with
        | none => exact Or.inr ⟨_, Step.scopeDPMoved hr hsl⟩
        | some v => exact Or.inr ⟨_, Step.scopeDP hr hsl⟩
  | @rbind Γ Δ1 F p k Ep hp hm hl hroots _ _ _ ih =>
    intro m hcd hi
    have hi0 : Inv m Γ F k := hi.rbindIn hp hroots
    obtain ⟨w, hpb⟩ : ∃ w, m.st p = some ⟨false, w⟩ := by
      obtain ⟨⟨o, w⟩, hsl, _, hso, _⟩ := hi.slot p Ep hp
      rw [hm] at hso; simp [Mode.ownSlot] at hso; subst hso; exact ⟨w, hsl⟩
    rcases ih hcd hi0 with rfl | ⟨r, hr⟩
    · exact Or.inr ⟨_, Step.rbindSkip hpb⟩
    · cases r with
      | ok m' k' => exact Or.inr ⟨_, Step.rbindIn hr⟩
      | panic m1 =>
        obtain ⟨hout, _⟩ := panic_unwind hr hi.heap hi.cover hi0.spineNd
        have hps : p ∉ k.spine := by
          have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
        exact Or.inr ⟨_, Step.rbindP hr (by rw [hout p hps]; exact hpb)⟩
  | frozen _ hz ih =>
    intro m hcd hi
    rcases ih hcd (hi.frozenIn hz) with h | ⟨r, hr⟩
    · subst h; exact Or.inr ⟨_, Step.frozenSkip⟩
    · cases r with
      | ok m' k' => exact Or.inr ⟨_, Step.frozenIn hr⟩
      | panic => exact Or.inr ⟨_, Step.frozenP hr⟩
  | @assign Γ Γ1 F x r Ex E hx _ _ hr _ _ _ _ =>
    intro m hcd hi
    obtain ⟨res, hres⟩ := evalR_exists hi.toMInv (hi.leafAnch rfl) hr
    cases res with
    | panic => exact Or.inr ⟨_, Step.assignP hres⟩
    | ok v o m1 =>
      obtain ⟨post, _⟩ := rhs_pres hi.toMInv (hi.leafAnch rfl) hr hres
      have hx1 : (Γ1 x).isSome := by rw [post.cdom, hx]; rfl
      obtain ⟨Ex1, hEx1⟩ := Option.isSome_iff_exists.mp hx1
      obtain ⟨sl, a', hsl, hd⟩ := dropSlot_exists post.inv hEx1
      exact Or.inr ⟨_, Step.assign (by rw [← hi.dom x, hx]; rfl) hres hsl hd⟩
  | ite _ _ hc _ _ _ _ =>
    intro m hcd hi
    obtain ⟨n, hn⟩ := eval_exists hi.toMInv hc
    by_cases h0 : n = 0
    · subst h0; exact Or.inr ⟨_, Step.iteF hn⟩
    · exact Or.inr ⟨_, Step.iteT hn h0⟩
  | «while» _ _ _ _ => exact fun _ _ => Or.inr ⟨_, Step.while⟩
  | @push Γ Γ1 F x y Ex Ey Ex1 t D hx hl hty hcan hxF hy hly htyy hyx hpa _ _ _ =>
    intro m hcd hi
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
  | @free Γ F x E t hx hl hm hty _ _ =>
    intro m hcd hi
    obtain ⟨T, hT, hwf, _⟩ := hi.own_val hx hl (by rw [hm]; rfl)
    obtain ⟨a', ha⟩ := frees_owned hi.heap hT hwf
    exact Or.inr ⟨_, Step.free hT ha⟩

  | panic => exact fun _ _ => Or.inr ⟨_, Step.panic⟩
  | @letrec Γ Γ1 Δ F x f k E fn _ hx _ hf hp _ _ _ _ _ _ =>
    intro m hcd hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    exact Or.inr ⟨_, Step.letrec hf hp hmx⟩
  | callc _ hx hxF hc htc hj hσ hhd _ hcT hnz _ _ _ =>
    intro m hcd hi
    exact Or.inr (hclo hx hxF hc htc hj hσ hhd hcT hnz hcd hi)
  | @catchR Γ Δ F x m0 s _ _ hM _ hKO _ ih =>
    intro m hcd hi
    rcases ih hcd hi.catchIn with rfl | ⟨r, hr⟩
    · exact Or.inr ⟨_, Step.catchSkip⟩
    · cases r with
      | ok m' s' => exact Or.inr ⟨_, Step.catchIn hr⟩
      | panic m1 =>
        obtain ⟨hout, _⟩ := panic_unwind hr hi.heap hi.cover hi.spineNd
        have hxs : x ∉ s.spine := hi.catchOK.2.1
        obtain ⟨Ex, hEx⟩ : ∃ Ex, Δ x = some Ex := by
          have := hM.dom x; simp at this; exact Option.isSome_iff_exists.mp this
        obtain ⟨_, E0, h0⟩ := hKO.2 x Ex hEx
        exact Or.inr ⟨_, Step.catchP hr (by rw [hout x hxs, ← hi.dom x, h0]; rfl)⟩

  | @unpair Γ Δ F y x z k E a b _ hy hl hm hty _ hx hz hxz _ _ _ _ _ _ _ _ =>
    intro m hcd hi
    obtain ⟨o, v, w, hv⟩ := pair_slot hi.toMInv hy hl hty
    obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rcases hm with h | ⟨b, h, _⟩ <;> rw [h] <;> rfl)
    rw [hT] at hv; cases hv
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    have hmz : m.st z = none := by
      have := hi.dom z; rw [hz] at this; cases h : m.st z <;> simp_all
    exact Or.inr ⟨_, Step.unpair hT hmx hmz hxz⟩

end A2

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

/-- …through a destructor type (A2-drop.3a: `getl` / `getr` lend a payload of
    a destructor enum). -/
theorem sum_slot_undtor {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {a b : Ty} (ht : E.ty.undtor = .sum a b) :
    ∃ v, (m.st y = some ⟨E.mode.ownSlot, some (.inl v)⟩) ∨ (m.st y = some ⟨E.mode.ownSlot, some (.inr v)⟩) := by
  rcases hi.mode_cases hy with hm | hm | hm
  · obtain ⟨T, hT, hw, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    have hw' := hw.undtor
    rw [ht] at hw'; rw [hm]
    cases hw' with
    | inl _ => exact ⟨_, Or.inl hT⟩
    | inr _ => exact ⟨_, Or.inr hT⟩
  all_goals
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    rw [← valOK_undtor, ht] at hok; rw [hm]
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
    obtain ⟨v, hv | hv⟩ := sum_slot_undtor hi hx hl ht
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

/-- A3.5's third cut: what a hand-over takes from a borrowed binding is an
    integer or a slice (`PushArg`), which holds no library handle. -/
theorem PushArg.bor_noCell {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {F : List Var} {y : Var} {E : Entry}
    {t : Ty} {D : List Dep} {Γ1 : Ctx} (hpa : PushArg Γ F y E t D Γ1) (hy : Γ y = some E)
    (hl : E.live = true) (hty : E.ty = t) {v : Val} (hv : m.st y = some ⟨false, some v⟩) :
    ∀ k, ¬ Sub (.cell k) v := by
  obtain ⟨sl, hsl, _, hso, _, hbor⟩ := hi.slot y E hy
  rw [hv] at hsl; cases hsl
  have hos : E.mode.ownSlot = false := by simpa using hso.symm
  obtain ⟨w, hw, hok⟩ := hbor hos hl
  cases hw
  intro k hs
  cases hpa with
  | move _ hm _ _ _ => rw [hm] at hos; cases hos
  | int => rw [hty] at hok; obtain ⟨n, rfl⟩ := valOK_int.mp hok; cases hs
  | slice => rw [hty] at hok; obtain ⟨d, o, l, rfl, _⟩ := valOK_slice.mp hok; cases hs

/-- A live binding has a value to hand on. -/
theorem takeVal_exists {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {F : List Var} {t : Ty} {D : List Dep} {Γ1 : Ctx} (hpa : PushArg Γ F y E t D Γ1)
    (hty : E.ty = t) : ∃ v m1, TakeVal m y v m1 := by
  rcases hi.mode_cases hy with hm | hm | hm
  · obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    exact ⟨T, _, TakeVal.own hT⟩
  all_goals
    obtain ⟨v, hv, _⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    exact ⟨v, m, TakeVal.bor hv (hpa.bor_noCell hi hy hl hty hv)⟩

/-- A live struct binding holds a struct. -/
theorem pair_slot {m : Mem} {Γ : Ctx} (hi : MInv m Γ) {y : Var} {E : Entry} (hy : Γ y = some E)
    (hl : E.live = true) {a b : Ty} (ht : E.ty.undtor = .prod a b) :
    ∃ o v w, m.st y = some ⟨o, some (.pair v w)⟩ := by
  rcases hi.mode_cases hy with hm | hm | hm
  · obtain ⟨T, hT, hw, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    have hw' := hw.undtor
    rw [ht] at hw'; cases hw'
    exact ⟨_, _, _, hT⟩
  all_goals
    obtain ⟨v, hv, hok⟩ := hi.bor_val hy hl (by rw [hm]; rfl)
    rw [← valOK_undtor, ht] at hok; obtain ⟨x, z, rfl, _⟩ := valOK_prod.mp hok
    exact ⟨_, _, _, hv⟩

theorem evalR_exists {m : Mem} {Γ Γ1 : Ctx} {F : List Var} {r : Rhs} {E : Entry} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F)
    (hr : RhsT Γ F r E Γ1) (hnb : ¬ RBlocked m r) : ∃ res, EvalR m r res := by
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
  | moveUp hy hl hm =>
    obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
    exact ⟨_, EvalR.moveOwn hT⟩
  | copyUp hy hl hm =>
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
  | @remove y ix E' t hy hl ht hcan _ _ hix =>
    have hm : E'.mode = .own := by
      rcases hcan with h | ⟨b, h, _⟩
      · exact h
      · exact absurd h (hi.noInout y E' b hy)
    obtain ⟨c, d, es, ⟨hac, had, hvec⟩, _⟩ := hi.vec_node hy hl ht
    obtain ⟨n, hn⟩ := eval_exists hi hix
    rcases hvec with h | ⟨h, _⟩
    · by_cases hlt : n < es.length
      · exact ⟨_, EvalR.remove hlt h hac had hn⟩
      · exact ⟨_, EvalR.removeOOB h hn (by omega)⟩
    · obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hm]; rfl)
      rw [hT] at h; cases h
  | @pair y z Ey Ez Γ1 Γ2 Dy Dz hy hly hpa1 hz hlz hpa2 _ =>
    obtain ⟨v, m1, htk1⟩ := takeVal_exists hi hy hly hpa1 rfl
    obtain ⟨post1, _⟩ := push_take hi hanch hy hly rfl hpa1 htk1
    obtain ⟨w, m2, htk2⟩ := takeVal_exists post1.inv hz hlz hpa2 rfl
    exact ⟨_, EvalR.pair htk1 htk2⟩
  | fst hy hl ht =>
    obtain ⟨o, v, w, hv⟩ := pair_slot hi hy hl ht
    exact ⟨_, EvalR.fst hv⟩
  | snd hy hl ht =>
    obtain ⟨o, v, w, hv⟩ := pair_slot hi hy hl ht
    exact ⟨_, EvalR.snd hv⟩
  | inl hy hly hpa _ =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa rfl
    exact ⟨_, EvalR.inl htk⟩
  | inr hy hly hpa _ =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa rfl
    exact ⟨_, EvalR.inr htk⟩
  | pack hy hly hte hpa _ _ =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa hte
    exact ⟨_, EvalR.pack htk⟩
  | getl hy hl ht =>
    obtain ⟨v, hv | hv⟩ := sum_slot_undtor hi hy hl ht
    · exact ⟨_, EvalR.getl hv⟩
    · exact ⟨_, EvalR.getlP hv⟩
  | getr hy hl ht =>
    obtain ⟨v, hv | hv⟩ := sum_slot_undtor hi hy hl ht
    · exact ⟨_, EvalR.getrP hv⟩
    · exact ⟨_, EvalR.getr hv⟩
  | takel hy hl hm ht _ _ =>
    obtain ⟨v, hv | hv⟩ := sum_slot_undtor hi hy hl (take_undtor ht) <;> rw [hm] at hv
    · exact ⟨_, EvalR.takel hv⟩
    · exact ⟨_, EvalR.takelP hv⟩
  | taker hy hl hm ht _ _ =>
    obtain ⟨v, hv | hv⟩ := sum_slot_undtor hi hy hl (take_undtor ht) <;> rw [hm] at hv
    · exact ⟨_, EvalR.takerP hv⟩
    · exact ⟨_, EvalR.taker hv⟩
  | arcNew hy hly hty _ _ _ hpa =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa hty
    -- the key `nid` is fresh: every block's key is below it
    have hfr : m1.blk m1.nid = none := by
      have hb := TakeVal.blk htk
      have hn : m1.nid = m.nid := by cases htk <;> rfl
      rw [hb, hn]
      cases h : m.blk m.nid with
      | none => rfl
      | some bl => exact absurd (hi.heap.bkey _ bl h) (Nat.lt_irrefl _)
    exact ⟨_, EvalR.arcNew htk hfr⟩
  | lockNew hy hly hty _ _ hpa =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa hty
    -- the key `nid` is fresh: every block's key is below it
    have hfr : m1.blk m1.nid = none := by
      have hb := TakeVal.blk htk
      have hn : m1.nid = m.nid := by cases htk <;> rfl
      rw [hb, hn]
      cases h : m.blk m.nid with
      | none => rfl
      | some bl => exact absurd (hi.heap.bkey _ bl h) (Nat.lt_irrefl _)
    by_cases hck : SendCheck m1.blk [v] m1.st
    · exact ⟨_, EvalR.lockNew htk hfr hck⟩
    · exact ⟨_, EvalR.lockNewFail htk hck⟩
  | arcClone ha hl hty =>
    obtain ⟨o, k, p, hv⟩ := hi.arc_slot ha hl hty
    exact ⟨_, EvalR.arcClone hv⟩
  | lockClone ha hl hty =>
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    exact ⟨_, EvalR.lockClone hv⟩
  | cellNew hy hly hty _ _ hpa =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa hty
    -- the key `nid` is fresh: every block's key is below it
    have hfr : m1.blk m1.nid = none := by
      have hb := TakeVal.blk htk
      have hn : m1.nid = m.nid := by cases htk <;> rfl
      rw [hb, hn]
      cases h : m.blk m.nid with
      | none => rfl
      | some bl => exact absurd (hi.heap.bkey _ bl h) (Nat.lt_irrefl _)
    by_cases hck : SendCheck m1.blk [v] m1.st
    · exact ⟨_, EvalR.cellNew htk hfr hck⟩
    · exact ⟨_, EvalR.cellNewFail htk hck⟩
  | cellClone ha hl hty =>
    obtain ⟨o, k, hv⟩ := hi.cell_slot ha hl hty
    exact ⟨_, EvalR.cellClone hv (hi.cell_owned ha hl hv (Sub.refl _))⟩
  | @glob g t _ _ =>
    -- A3.6: the global's share, or a panic if the store holds none of that type
    by_cases h : ∃ v, m.gl g = some v ∧ GlobFits m.blk t v
    · obtain ⟨v, hv, hf⟩ := h
      exact ⟨_, EvalR.glob hv hf⟩
    · exact ⟨_, EvalR.globP h⟩
  | rwRead ha hl hty =>
    -- A3.3: a new view of the payload, unless a writer has it checked out
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    have hfr : m.blk m.nid = none := by
      cases h : m.blk m.nid with
      | none => rfl
      | some bl => exact absurd (hi.heap.bkey _ bl h) (Nat.lt_irrefl _)
    cases ob with
    | none => exact absurd ⟨o, k, _, hv, hk⟩ hnb
    | some p => exact ⟨_, EvalR.rwRead hv hk hfr⟩
  | rwTryRead ha hl hty =>
    -- A3.3: a new view and its guard, or `none` where `rw_read` would wait
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    have hfr : m.blk m.nid = none := by
      cases h : m.blk m.nid with
      | none => rfl
      | some bl => exact absurd (hi.heap.bkey _ bl h) (Nat.lt_irrefl _)
    cases ob with
    | none => exact ⟨_, EvalR.rwTryReadNone hv hk⟩
    | some p => exact ⟨_, EvalR.rwTryRead hv hk hfr⟩
  | rwTryWrite ha hl hty =>
    -- A3.3: `some` where a write's check-out would not wait, `none` where it would
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    by_cases hnv : HasView m.blk k
    · exact ⟨_, EvalR.rwTryWriteNone hv (.inr hnv)⟩
    cases ob with
    | none => exact ⟨_, EvalR.rwTryWriteNone hv (.inl ⟨_, hk⟩)⟩
    | some p => exact ⟨_, EvalR.rwTryWrite hv hk hnv⟩
  | atomic ha hl hty he1 he2 =>
    -- A3.4: the word is there unless a `withLock` has it checked out
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    have hnv : ¬ HasView m.blk k := fun h => hnb ⟨o, k, hv, Or.inr h⟩
    cases ob with
    | none => exact absurd ⟨o, k, hv, Or.inl hk⟩ hnb
    | some p =>
      obtain ⟨_, _, hpay, _⟩ := hi.blocks k _ hk
      obtain ⟨hw, _⟩ := hpay p rfl
      cases hw with
      | int =>
        obtain ⟨n1, h1⟩ := eval_exists hi he1
        obtain ⟨n2, h2⟩ := eval_exists hi he2
        exact ⟨_, EvalR.atomic hv hk h1 h2 hnv⟩
  | chanSend ha hl hty hy hly htyy hpa =>
    -- A3.4: into the queue, or (closed) dropped, unless the channel's payload
    -- is checked out
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    have hnv : ¬ HasView m.blk k := fun h => hnb ⟨o, k, .int, hv, Or.inr h⟩
    cases ob with
    | none => exact absurd ⟨o, k, _, hv, Or.inl hk⟩ hnb
    | some p =>
      obtain ⟨_, _, hpay, _⟩ := hi.blocks k _ hk
      obtain ⟨hw, _⟩ := hpay p rfl
      obtain ⟨_, _, hall⟩ := hi.heap.blk k _ hk
      obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa htyy
      have hb1 : m1.blk = m.blk := by cases htk <;> rfl
      have ha1 : m1.alloc = m.alloc := by cases htk <;> rfl
      -- A3.5's second cut: the crossing check first
      by_cases hck : SendCheck m1.blk [v] m1.st
      case neg => exact ⟨_, EvalR.chanSendFail htk hck⟩
      cases hw with
      | pair hq hf =>
        cases hq with
        | @node _ c d es _ =>
          cases hf with
          | @int f =>
            cases f with
            | zero =>
              exact ⟨_, EvalR.chanSend hv htk (by rw [hb1]; exact hk)
                (by rw [ha1]; exact (hall c (by simp [Blk.tree])).1)
                (by rw [ha1]; exact (hall d (by simp [Blk.tree])).1) (by rw [hb1]; exact hnv) hck⟩
            | succ f =>
              obtain ⟨_, hp⟩ := push_take hi hanch hy hly htyy hpa htk
              obtain ⟨a', hfr⟩ := frees_exists hp.wf m1.alloc hp.nd (fun i hi' => (hp.al i hi').1)
              exact ⟨_, EvalR.chanSendClosed hv htk (by rw [hb1]; exact hk) hfr hck⟩
  | @chanRecv w a E s ha hl hty =>
    -- A3.4: the queue's head, or none, unless the channel's payload is
    -- checked out or (`chan_recv`) its queue is empty and open
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    have hnv : ¬ HasView m.blk k := fun h => hnb ⟨o, k, .int, hv, Or.inr (Or.inr h)⟩
    cases ob with
    | none => exact absurd ⟨o, k, _, hv, Or.inl hk⟩ hnb
    | some p =>
      obtain ⟨_, _, hpay, _⟩ := hi.blocks k _ hk
      obtain ⟨hw, _⟩ := hpay p rfl
      obtain ⟨_, _, hall⟩ := hi.heap.blk k _ hk
      cases hw with
      | pair hq hf =>
        cases hq with
        | @node _ c d es _ =>
          cases hf with
          | @int f =>
            have hc : m.alloc c = true := (hall c (by simp [Blk.tree])).1
            cases es with
            | cons v es =>
              have hd : m.alloc d = true := (hall d (by simp [Blk.tree])).1
              by_cases hck : RecvCheck v es
              · exact ⟨_, EvalR.chanRecv hv hk hc hd hnv hck⟩
              · exact ⟨_, EvalR.chanRecvFail hv hk hck⟩
            | nil =>
              by_cases hb : w = true ∧ f = 0
              · obtain ⟨rfl, rfl⟩ := hb
                exact absurd ⟨o, k, _, hv, Or.inr (Or.inl ⟨rfl, _, _, _, hk⟩)⟩ hnb
              · exact ⟨_, EvalR.chanRecvNone hv hk hc (by cases w <;> simp_all)⟩
  | chanClose ha hl hty =>
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    have hnv : ¬ HasView m.blk k := fun h => hnb ⟨o, k, .int, hv, Or.inr h⟩
    cases ob with
    | none => exact absurd ⟨o, k, _, hv, Or.inl hk⟩ hnb
    | some p =>
      obtain ⟨_, _, hpay, _⟩ := hi.blocks k _ hk
      obtain ⟨hw, _⟩ := hpay p rfl
      cases hw with
      | pair _ hf =>
        cases hf with
        | int => exact ⟨_, EvalR.chanClose hv hk hnv⟩
  | lockTake ha hl hty =>
    -- A3.2's second cut: the payload, unless it is out or read
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    have hnv : ¬ HasView m.blk k := fun h => hnb ⟨o, k, .int, hv, Or.inr h⟩
    cases ob with
    | none => exact absurd ⟨o, k, _, hv, Or.inl hk⟩ hnb
    | some p => exact ⟨_, EvalR.lockTake hv hk hnv⟩
  | lockRestore ha hl hty hy hly htyy hpa =>
    -- ... a restore puts the value back, or panics: it never waits
    obtain ⟨o, k, hv⟩ := hi.lk_slot ha hl hty
    obtain ⟨ob, hk⟩ := hi.lk_val ha hl hty hv
    cases ob with
    | none =>
      obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa htyy
      have hb1 : m1.blk = m.blk := by cases htk <;> rfl
      by_cases hck : SendCheck m1.blk [v] m1.st
      · exact ⟨_, EvalR.lockRestore hv htk (by rw [hb1]; exact hk) hck⟩
      · exact ⟨_, EvalR.lockRestoreFail htk hck⟩
    | some p => exact ⟨_, EvalR.lockRestoreP hv hk⟩
  | arcGet ha hl hty _ _ =>
    obtain ⟨o, k, p, hv⟩ := hi.arc_slot ha hl hty
    obtain ⟨bl, hbl, _⟩ := (hi.arc_val ha hl hty hv).1.rd
    exact ⟨_, EvalR.arcGet hv hbl⟩

/-- A part of a tree whose addresses are distinct has distinct addresses. -/
theorem Sub.nodup {a b : Val} (h : Sub a b) (hn : b.ids.Nodup) : a.ids.Nodup := by
  induction h with
  | refl => exact hn
  | child he _ ih => exact ih (Child.nodup (Child.elem he) hn)
  | fst _ ih => exact ih (Child.nodup Child.fst hn)
  | snd _ ih => exact ih (Child.nodup Child.snd hn)
  | inl _ ih => exact ih (Child.nodup Child.inl hn)
  | inr _ ih => exact ih (Child.nodup Child.inr hn)
  | pkg _ ih => exact ih (Child.nodup Child.pkg hn)

/-- Well-formed elements whose addresses are distinct and live can be freed. -/
theorem freesL_exists {τ : Ty} : ∀ {l : List Val}, (∀ e ∈ l, WFv τ e) → ∀ a : Nat → Bool,
    (idsL l).Nodup → (∀ i ∈ idsL l, a i = true) → ∃ a', FreesL a l a'
  | [], _, a, _, _ => ⟨a, FreesL.nil⟩
  | e :: l, hw, a, hnd, ha => by
    simp only [idsL_cons, List.nodup_append] at hnd
    obtain ⟨a1, h1⟩ := frees_exists (hw e (by simp)) a hnd.1 (fun i hi => ha i (by simp [hi]))
    obtain ⟨a2, h2⟩ := freesL_exists (fun x hx => hw x (by simp [hx])) a1 hnd.2.1 (by
      intro i hi
      have hne : i ∉ e.ids := fun h => hnd.2.2 i h i hi rfl
      rw [h1.other hne]; exact ha i (by simp [hi]))
    exact ⟨a2, FreesL.cons h1 h2⟩

/-- Agora #295: a change through a borrow finds the node in its owner's tree
    (`MInv.thru_owner`), and steps. -/
theorem progress_editB {P : Prog} {m : Mem} {Γ Γ1 : Ctx} {F : List Var} (hi : MInv m Γ)
    (hanch : RootbAnch Γ F) {x : Var} {op : Edit} {Ex Ex1 : Entry} {t : Ty} {D : List Dep}
    (hx : Γ x = some Ex) (hmx : Ex.mode = .bor) (hl : Ex.live = true) (hty : Ex.ty = .vec t)
    (harg : EditArg Γ F op t D Γ1) (hyx : ∀ y, op.stored = some y → y ≠ x) (hx1 : Γ1 x = some Ex1)
    (hl1 : Ex1.live = true) (hthru : ThruOK Γ1 F op Ex.ty Ex1.path) :
    ∃ r, Step P m (.edit true x op) r := by
  have hE1 : Ex1 = Ex := harg.at_ne hyx hx hx1 hl1
  rw [hE1] at hx1 hthru
  have hro : ∀ d ∈ memDeps Ex.path, ∃ Er, Γ1 d.root = some Er ∧ Er.mode.ownSlot = true :=
    fun d hd => by
      obtain ⟨_, _, Er, hEr, _, hcan, _⟩ := hthru d hd
      exact ⟨Er, hEr, hcan.ownSlot⟩
  cases harg with
  | push hy hly htyy hpa =>
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa htyy
    obtain ⟨post, _⟩ := push_take hi hanch hy hly htyy hpa htk
    obtain ⟨_, _, _, _, c, d, es, _, _, _, _, _, _, hno, _⟩ := post.inv.thru_owner hx1 hmx hl hty hro hthru.noShare
    obtain ⟨T', hr⟩ := Repl.exists hno.sub (.node t c d (es ++ [v]))
    exact ⟨_, Step.editPush htk hno hr⟩
  | trunc hie =>
    obtain ⟨n, hev⟩ := eval_exists hi hie
    obtain ⟨dep, _, T, _, c, d, es, _, hT, _, _, _, hw, hno, _⟩ := hi.thru_owner hx1 hmx hl hty hro hthru.noShare
    have hsub := hno.sub
    have hndT : (Val.node t c d es).ids.Nodup := hsub.nodup (hi.heap.nodup _ _ hT)
    have hnd : (idsL (es.drop n)).Nodup := by
      simp only [ids_node, List.nodup_cons] at hndT
      have h2 := hndT.2.2
      rw [← List.take_append_drop n es, idsL_append] at h2
      exact (List.nodup_append.mp h2).2.1
    have hal : ∀ i ∈ idsL (es.drop n), m.alloc i = true := fun i hi' =>
      (hi.heap.alloc _ _ hT i (hsub.ids i (ids_drop_sub hi'))).1
    have hwe : ∀ e ∈ es.drop n, WFv t e := by
      cases hw with
      | node hes => exact fun e he => hes e (List.mem_of_mem_drop he)
    obtain ⟨a', hfr⟩ := freesL_exists hwe m.alloc hnd hal
    obtain ⟨T', hr⟩ := Repl.exists hsub (.node t c d (es.take n))
    exact ⟨_, Step.editTrunc hev hno hfr hr⟩
  | set hie hy hly htyy hpa =>
    obtain ⟨n, hev⟩ := eval_exists hi hie
    obtain ⟨v, m1, htk⟩ := takeVal_exists hi hy hly hpa htyy
    obtain ⟨post, hp⟩ := push_take hi hanch hy hly htyy hpa htk
    obtain ⟨_, _, T, _, c, d, es, _, hT, _, _, _, hw, hno, _⟩ := post.inv.thru_owner hx1 hmx hl hty hro hthru.noShare
    by_cases hn : n < es.length
    · -- the old element is freed
      have hsn : Sub es[n] T := (Sub.child (List.getElem_mem hn) (Sub.refl _)).trans hno.sub
      have hwe : WFv t es[n] := by
        cases hw with
        | node hes => exact hes _ (List.getElem_mem hn)
      obtain ⟨a', hfr⟩ := frees_exists hwe m1.alloc (hsn.nodup (post.inv.heap.nodup _ _ hT))
        (fun i hi' => (post.inv.heap.alloc _ _ hT i (hsn.ids i hi')).1)
      obtain ⟨T', hr⟩ := Repl.exists hno.sub (.node t c d (es.set n v))
      exact ⟨_, Step.editSet hn hev htk hno hfr hr⟩
    · -- out of range: the value is freed
      obtain ⟨a', hfr⟩ := frees_exists hp.wf m1.alloc hp.nd (fun i hi' => (hp.al i hi').1)
      exact ⟨_, Step.editSetOOB hev htk hno (by omega) hfr⟩

/-- Progress for every statement but a call, given the call case. -/
theorem progress {P : Prog}
    (hcall : ∀ {Γ : Ctx} {F : List Var} {x : Var} {f : Nat} {args : List Var} {k : Stmt}
      {E : Entry} {Γ1 : Ctx} {m : Mem}, Γ x = none → CallT P Γ F f args E Γ1 → MInv m Γ →
      ∃ r, Step P m (.letcall x f args k) r)
    (hclo : ∀ {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat} {zs : List Var} {k : Stmt}
      {Ec E : Entry} {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} {m : Mem},
      Γ x = none → x ∉ F → Γ c = some Ec → Ec.ty.undtor = .fn ms q → ms[j]? = some σ → P[σ]? = some sig →
      sig.params.head? = some (.inp, Ec.ty) → CallT P Γ F σ (c :: zs) E Γ1 →
      (∀ z ∈ zs, ∀ d ∈ Ec.vdeps, d.kind.bound ≠ .none → d.root ≠ z) →
      MemCodes P m → Inv m Γ F (.callc x c j zs k) → ∃ r, Step P m (.callc x c j zs k) r)
    (hhand : ∀ {Γ Γ1 : Ctx} {F : List Var} {x c : Var} {j : Nat} {k : Stmt} {Ec E : Entry}
      {ms : List Nat} {q : Cross} {σ : Nat} {sig : Fn} {b : Eff} {m : Mem},
      Γ x = none → Γ c = some Ec → Ec.ty.undtor = .fn ms q → canDo Ec.mode .replace → ms[j]? = some σ →
      P[σ]? = some sig →
      ((sig.params = [(.inout b, .fn ms q)] ∧ Ec.ty = .fn ms q ∧ Cross.send.Le q) ∨
      (sig.params = [(.sink, Ec.ty)] ∧ Ec.vdeps = [] ∧ Ec.mode = .own ∧ Ec.live = true ∧
        q.drops = true ∧ sig.resOwn = false)) → CallT P (kill .replace false c Γ) F σ [c] E Γ1 →
      MemCodes P m → Inv m Γ F (.callcE x c j [] k) → ∃ r, Step P m (.callcE x c j [] k) r)
    {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (ht : StmtT P Γ F s Δ) :
    ∀ {m : Mem}, MemCodes P m → Inv m Γ F s → s = .skip ∨ Blocked m s ∨ ∃ r, Step P m s r := by
  induction ht with
  | skip => exact fun _ _ => Or.inl rfl
  | sub hw _ _ ih => exact fun hcd hi => ih hcd (hi.weaker hw)
  | seq _ _ _ iha _ =>
    intro m hcd hi
    rcases iha hcd hi.seqIn with rfl | hbl | ⟨r, hr⟩
    · exact Or.inr <| Or.inr ⟨_, Step.seqSkip⟩
    · exact Or.inr (Or.inl hbl)
    · cases r with
      | ok m' a' => exact Or.inr <| Or.inr ⟨_, Step.seqL hr⟩
      | panic => exact Or.inr <| Or.inr ⟨_, Step.seqP hr⟩
  | @letv Γ Γ1 Δ F x r k E _ hx _ hr _ _ _ =>
    intro m hcd hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    by_cases hrb : RBlocked m r
    · exact Or.inr (Or.inl hrb)
    obtain ⟨res, hres⟩ := evalR_exists hi.toMInv (hi.leafAnch rfl) hr hrb
    cases res with
    | ok v o m1 => exact Or.inr <| Or.inr ⟨_, Step.letv hmx hres⟩
    | panic => exact Or.inr <| Or.inr ⟨_, Step.letvP hres⟩
  | @letcall Γ Γ1 Δ F x f args k E _ hx _ hc _ _ _ _ =>
    intro m hcd hi
    exact Or.inr <| Or.inr (hcall (k := k) hx hc hi.toMInv)
  | @scope Γ Δ1 F x k hxE _ _ _ ih =>
    intro m hcd hi
    obtain ⟨Ex, hx, hnrb⟩ := hxE
    have hi0 : Inv m Γ F k := hi.scopeIn hx hnrb
    rcases ih hcd hi0 with rfl | hbl | ⟨r, hr⟩
    · obtain ⟨sl, a', hsl, hd⟩ := dropSlot_exists hi.toMInv hx
      exact Or.inr <| Or.inr ⟨_, Step.scopeSkip hsl hd⟩
    · exact Or.inr (Or.inl hbl)
    · cases r with
      | ok m' k' => exact Or.inr <| Or.inr ⟨_, Step.scopeIn hr⟩
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
        exact Or.inr <| Or.inr ⟨_, Step.scopeP hr hsl1 hd⟩
  | @withLock Γ Δ F a x k Ea t _ hx _ ha hla hta _ _ _ _ _ _ =>
    intro m hcd hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    obtain ⟨kk, hv⟩ := hi.lockOf_slot ha hla hta
    obtain ⟨ob, hk⟩ := hi.lockOf_val ha hla hta hv
    -- A3.3: a writer also waits while a view of the block lives
    by_cases hnv : HasView m.blk kk
    · exact Or.inr (Or.inl ⟨kk, t, hv, Or.inr hnv⟩)
    cases ob with
    | none => exact Or.inr (Or.inl ⟨kk, t, hv, Or.inl hk⟩)
    | some w => exact Or.inr <| Or.inr ⟨_, Step.withLock hv hk hmx hnv⟩
  | @scopeL Γ Δ1 F kk t x k hxE _ _ _ ih =>
    intro m hcd hi
    obtain ⟨Ex, hx, hnrb, _⟩ := hxE
    have hi0 : Inv m Γ F k := hi.scopeLIn hx hnrb
    rcases ih hcd hi0 with rfl | hbl | ⟨r, hr⟩
    · obtain ⟨sl, a', hsl, hd⟩ := dropSlot_exists hi.toMInv hx
      -- the payload goes back into its block, or `x`'s slot is dropped
      obtain ⟨m', hrl⟩ := Release.exists (k := kk) (t := t) hsl hd
      -- A3.5's second cut: unless it fails the crossing check, which panics
      by_cases hck : GiveCheck m x sl
      · exact Or.inr <| Or.inr ⟨_, Step.scopeLSkip hrl fun sl' h => by rw [hsl] at h; cases h; exact hck⟩
      · exact Or.inr <| Or.inr ⟨_, Step.scopeLFail hsl hck⟩
    · exact Or.inr (Or.inl hbl)
    · cases r with
      | ok m' k' => exact Or.inr <| Or.inr ⟨_, Step.scopeLIn hr⟩
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
        -- A3.3: on the way out too
        obtain ⟨m2, hrl⟩ := Release.exists (k := kk) (t := t) hsl1 hd
        exact Or.inr <| Or.inr ⟨_, Step.scopeLP hr hrl⟩
  | @letd Γ Γ1 Δ F x f r k E _ _ _ _ hx _ hr _ _ _ _ _ _ _ _ =>
    intro m hcd hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    by_cases hrb : RBlocked m r
    · exact Or.inr (Or.inl hrb)
    obtain ⟨res, hres⟩ := evalR_exists hi.toMInv (hi.leafAnch rfl) hr hrb
    cases res with
    | ok v o m1 => exact Or.inr <| Or.inr ⟨_, Step.letd hmx hres⟩
    | panic => exact Or.inr <| Or.inr ⟨_, Step.letdP hres⟩
  | @scopeD Γ Δ1 F x f k hxE _ _ _ _ _ _ _ ih =>
    intro m hcd hi
    obtain ⟨Ex, _, hx, hmo, _, _, _⟩ := hxE
    have hnrb : Ex.mode ≠ .rootb := by rw [hmo]; simp
    have hiS : Inv m Γ F (.scope x k) := Inv.scopeD_iff.mp hi
    have hi0 : Inv m Γ F k := hiS.scopeIn hx hnrb
    -- `x` owns its slot: a value, or none once moved
    have hown : ∀ m' : Mem, m'.st x = m.st x → ∃ val, m'.st x = some ⟨true, val⟩ := by
      intro m' he
      obtain ⟨⟨o, val⟩, hsl, _, hso, _⟩ := hi.slot x Ex hx
      rw [hmo] at hso; simp [Mode.ownSlot] at hso; subst hso; exact ⟨val, by rw [he, hsl]⟩
    rcases ih hcd hi0 with rfl | hbl | ⟨r, hr⟩
    · obtain ⟨val, hsl⟩ := hown m rfl
      cases val with
      | none => exact Or.inr <| Or.inr ⟨_, Step.scopeDMoved hsl⟩
      | some v =>
        -- (A2-drop.3b: a `Vec`'s node is drained, element by element)
        cases v with
        | node t c d es =>
          cases es with
          | nil => exact Or.inr <| Or.inr ⟨_, Step.scopeDEmpty hsl⟩
          | cons e es => exact Or.inr <| Or.inr ⟨_, Step.scopeDDrain hsl⟩
        | _ => exact Or.inr <| Or.inr ⟨_, Step.scopeDEnd hsl rfl⟩
    · exact Or.inr (Or.inl hbl)
    · cases r with
      | ok m' k' => exact Or.inr <| Or.inr ⟨_, Step.scopeDIn hr⟩
      | panic m1 =>
        obtain ⟨hout, _⟩ := panic_unwind hr hi.heap hi.cover hi0.spineNd
        have hxs : x ∉ k.spine := by
          have := hiS.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
        obtain ⟨val, hsl⟩ := hown m1 (hout x hxs)
        cases val with
        | none => exact Or.inr <| Or.inr ⟨_, Step.scopeDPMoved hr hsl⟩
        | some v =>
          cases v with
          | node t c d es => exact Or.inr <| Or.inr ⟨_, Step.scopeDPDrain hr hsl⟩
          | _ => exact Or.inr <| Or.inr ⟨_, Step.scopeDP hr hsl rfl⟩
  | @rbind Γ Δ1 F p k Ep hp hm hl hroots _ _ _ ih =>
    intro m hcd hi
    have hi0 : Inv m Γ F k := hi.rbindIn hp hroots
    obtain ⟨w, hpb⟩ : ∃ w, m.st p = some ⟨false, w⟩ := by
      obtain ⟨⟨o, w⟩, hsl, _, hso, _⟩ := hi.slot p Ep hp
      rw [hm] at hso; simp [Mode.ownSlot] at hso; subst hso; exact ⟨w, hsl⟩
    rcases ih hcd hi0 with rfl | hbl | ⟨r, hr⟩
    · exact Or.inr <| Or.inr ⟨_, Step.rbindSkip hpb⟩
    · exact Or.inr (Or.inl hbl)
    · cases r with
      | ok m' k' => exact Or.inr <| Or.inr ⟨_, Step.rbindIn hr⟩
      | panic m1 =>
        obtain ⟨hout, _⟩ := panic_unwind hr hi.heap hi.cover hi0.spineNd
        have hps : p ∉ k.spine := by
          have := hi.spineNd; simp only [Stmt.spine, List.nodup_cons] at this; exact this.1
        exact Or.inr <| Or.inr ⟨_, Step.rbindP hr (by rw [hout p hps]; exact hpb)⟩
  | frozen _ hz ih =>
    intro m hcd hi
    rcases ih hcd (hi.frozenIn hz) with h | hbl | ⟨r, hr⟩
    · subst h; exact Or.inr <| Or.inr ⟨_, Step.frozenSkip⟩
    · exact Or.inr (Or.inl hbl)
    · cases r with
      | ok m' k' => exact Or.inr <| Or.inr ⟨_, Step.frozenIn hr⟩
      | panic => exact Or.inr <| Or.inr ⟨_, Step.frozenP hr⟩
  | @assign Γ Γ1 F x r Ex E hx _ _ hr _ _ _ _ =>
    intro m hcd hi
    by_cases hrb : RBlocked m r
    · exact Or.inr (Or.inl hrb)
    obtain ⟨res, hres⟩ := evalR_exists hi.toMInv (hi.leafAnch rfl) hr hrb
    cases res with
    | panic => exact Or.inr <| Or.inr ⟨_, Step.assignP hres⟩
    | ok v o m1 =>
      obtain ⟨post, _⟩ := rhs_pres hi.toMInv (hi.leafAnch rfl) hr hres
      have hx1 : (Γ1 x).isSome := by rw [post.cdom, hx]; rfl
      obtain ⟨Ex1, hEx1⟩ := Option.isSome_iff_exists.mp hx1
      obtain ⟨sl, a', hsl, hd⟩ := dropSlot_exists post.inv hEx1
      exact Or.inr <| Or.inr ⟨_, Step.assign (by rw [← hi.dom x, hx]; rfl) hres hsl hd⟩
  | ite _ _ hc _ _ _ _ =>
    intro m hcd hi
    obtain ⟨n, hn⟩ := eval_exists hi.toMInv hc
    by_cases h0 : n = 0
    · subst h0; exact Or.inr <| Or.inr ⟨_, Step.iteF hn⟩
    · exact Or.inr <| Or.inr ⟨_, Step.iteT hn h0⟩
  | «while» _ _ _ _ => exact fun _ _ => Or.inr <| Or.inr ⟨_, Step.while⟩
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
        exact ⟨v, m, TakeVal.bor hv (hpa.bor_noCell hi.toMInv hy hly htyy hv), rfl, rfl⟩
    obtain ⟨v, m1, htk, hst, hal⟩ := htake
    exact Or.inr <| Or.inr ⟨_, Step.push htk (by rw [hst]; exact hT) (by rw [hal]; exact hac)
      (by rw [hal]; exact had)⟩
  | @withElem Γ Γ1 Δ1 Δ F y x i k Ey' E _ hx _ _ _ he _ _ hr _ _ _ _ _ _ _ =>
    -- `y` owns a `Vec`: element `i` moves out, or the index is out of range
    intro m hcd hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    cases hr with
    | @pop _ E0 t hy0 hl0 hty0 hcan _ _ =>
    obtain ⟨Ey, hy, rfl⟩ : ∃ Ey, Γ y = some Ey ∧ E0 = killE .replace false y Ey := by
      simp only [A2.kill] at hy0
      cases h : Γ y with
      | none => rw [h] at hy0; cases hy0
      | some Ey => rw [h] at hy0; cases hy0; exact ⟨Ey, rfl, rfl⟩
    have hl : Ey.live = true := by
      unfold killE at hl0; split at hl0
      · cases hl0
      · exact hl0
    rw [killE_ty] at hty0
    rw [killE_mode] at hcan
    have hmy : Ey.mode = .own := by
      rcases hcan with h | ⟨b, h, _⟩
      · exact h
      · exact absurd h (hi.noInout y Ey b hy)
    obtain ⟨c, d, es, ⟨hac, had, hvec⟩, _⟩ := hi.vec_node hy hl hty0
    have hT : m.st y = some ⟨true, some (.node t c d es)⟩ := by
      rcases hvec with h | ⟨h, _⟩
      · exact h
      · obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rw [hmy]; rfl); rw [hT] at h; cases h
    obtain ⟨n, hn⟩ := eval_exists hi.toMInv he
    by_cases hlt : n < es.length
    · exact Or.inr <| Or.inr ⟨_, Step.withElem hlt hT hac had hn hmx⟩
    · exact Or.inr <| Or.inr ⟨_, Step.withElemOOB hT hac hn (by omega)⟩
  | @insert Γ Δ F x y i he _ _ ih =>
    -- the push it is typed as has a step, so it has one
    intro m hcd hi
    have hi0 : Inv m Γ F (.push x y) :=
      hi.respine rfl (fun v hv => by
        rcases List.mem_cons.mp hv with h | h
        · simp [Stmt.vars, h]
        · simp only [List.mem_singleton] at h; simp [Stmt.vars, h]) trivial trivial trivial
    obtain ⟨n, hn⟩ := eval_exists hi.toMInv he
    rcases ih hcd hi0 with h | h | ⟨r, hr⟩
    · cases h
    · exact absurd h (by simp [Blocked])
    · cases hr with
      | push htk hT hc hd => exact Or.inr <| Or.inr ⟨_, Step.insert hn htk hT hc hd⟩
      | pushRealloc htk hT hc hd => exact Or.inr <| Or.inr ⟨_, Step.insert hn htk hT hc hd⟩
      | waitPanic hw => exact absurd hw (by simp [Waits])
      | reap _ hk hnc => exact Or.inr <| Or.inr ⟨_, Step.reap rfl hk hnc⟩
  | @free Γ F x E t hx hl hm hty _ _ =>
    intro m hcd hi
    obtain ⟨T, hT, hwf, _⟩ := hi.own_val hx hl (by rw [hm]; rfl)
    obtain ⟨a', ha⟩ := frees_owned hi.heap hT hwf
    exact Or.inr <| Or.inr ⟨_, Step.free hT ha⟩
  | editB hx hmx hl hty _ _ harg hyx hx1 hl1 _ hthru =>
    intro m hcd hi
    exact Or.inr <| Or.inr (progress_editB hi.toMInv (hi.leafAnch rfl) hx hmx hl hty harg hyx hx1 hl1 hthru)
  | editBV hx hmx hl hty _ _ _ harg hyx hx1 hl1 _ hthru _ =>
    intro m hcd hi
    exact Or.inr <| Or.inr (progress_editB hi.toMInv (hi.leafAnch rfl) hx hmx hl hty harg hyx hx1 hl1 hthru)

  | panic => exact fun _ _ => Or.inr <| Or.inr ⟨_, Step.panic⟩
  | @letrec Γ Γ1 Δ F x f k E fn _ hx _ hf hp _ _ _ _ _ _ =>
    intro m hcd hi
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    exact Or.inr <| Or.inr ⟨_, Step.letrec hf hp hmx⟩
  | callc _ hx hxF hc htc hj hσ hhd _ hcT hnz _ _ _ =>
    intro m hcd hi
    exact Or.inr <| Or.inr (hclo hx hxF hc htc hj hσ hhd hcT hnz hcd hi)
  | callcE _ hx _ hc htc hcan _ hj hσ hsp _ _ _ _ _ hcT _ _ _ _ _ =>
    intro m hcd hi
    exact Or.inr <| Or.inr (hhand hx hc htc hcan hj hσ hsp hcT hcd hi)
  | @catchR Γ Δ F x m0 s _ _ hM _ hKO _ ih =>
    intro m hcd hi
    rcases ih hcd hi.catchIn with rfl | hbl | ⟨r, hr⟩
    · exact Or.inr <| Or.inr ⟨_, Step.catchSkip⟩
    · exact Or.inr (Or.inl hbl)
    · cases r with
      | ok m' s' => exact Or.inr <| Or.inr ⟨_, Step.catchIn hr⟩
      | panic m1 =>
        obtain ⟨hout, _⟩ := panic_unwind hr hi.heap hi.cover hi.spineNd
        have hxs : x ∉ s.spine := hi.catchOK.2.1
        obtain ⟨Ex, hEx⟩ : ∃ Ex, Δ x = some Ex := by
          have := hM.dom x; simp at this; exact Option.isSome_iff_exists.mp this
        obtain ⟨_, E0, h0⟩ := hKO.2 x Ex hEx
        exact Or.inr <| Or.inr ⟨_, Step.catchP hr (by rw [hout x hxs, ← hi.dom x, h0]; rfl)⟩

  | @unpair Γ Δ F y x z k E a b _ hy hl hm hty _ hx hz hxz _ _ _ _ _ _ _ _ _ _ =>
    intro m hcd hi
    obtain ⟨o, v, w, hv⟩ := pair_slot hi.toMInv hy hl (unpair_undtor hty)
    obtain ⟨T, hT, _⟩ := hi.own_val hy hl (by rcases hm with h | ⟨b, h, _⟩ <;> rw [h] <;> rfl)
    rw [hT] at hv; cases hv
    have hmx : m.st x = none := by
      have := hi.dom x; rw [hx] at this; cases h : m.st x <;> simp_all
    have hmz : m.st z = none := by
      have := hi.dom z; rw [hz] at this; cases h : m.st z <;> simp_all
    exact Or.inr <| Or.inr ⟨_, Step.unpair hT hmx hmz hxz⟩

end A2

import A2.Soundness

/-! A2 — Agora #610: the reaps that end a step always can be taken, and
end.

`Steps` takes a step only with the reaps after it (`Settle`): the thread
whose step the marking sweep ended hands every orphan it marked to a
destructor frame before anything else runs.  So that this asks nothing of a
run that it cannot give, a typed configuration with an orphan can always
reap one (`orphan_reaps`: from any typed statement, at its redex), and the
reaps end (`settle_total`: each empties an orphan, and the marking sweep
after it makes no new one it did not have the payload of).  Every step of a
typed configuration is therefore followed by a `Settle`, and `Steps` reaches
all that `Step` does, the reaps included. -/

namespace A2

/-- A statement whose frames lead to a source redex, where `Step.reap` can
    put a destructor frame. -/
inductive Reapable : Stmt → Prop
  | src {s : Stmt} : s.src = true → Reapable s
  | seq {a b : Stmt} : Reapable a → Reapable (.seq a b)
  | scope {x : Var} {s : Stmt} : Reapable s → Reapable (.scope x s)
  | rbind {p : Var} {s : Stmt} : Reapable s → Reapable (.rbind p s)
  | frozen {z : List Var} {s : Stmt} : Reapable s → Reapable (.frozen z s)
  | catchR {x : Var} {m0 : Mem} {s : Stmt} : Reapable s → Reapable (.catchR x m0 s)
  | scopeD {x : Var} {f : Nat} {s : Stmt} : Reapable s → Reapable (.scopeD x f s)
  | scopeL {k : Nat} {t : Ty} {x : Var} {s : Stmt} : Reapable s → Reapable (.scopeL k t x s)

/-- Every typed statement is one: a source form is source (its body, the
    rest of a sequence and the branches are, `StmtT`), and a run-time form
    is a frame around a typed statement. -/
theorem StmtT.reapable {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (h : StmtT P Γ F s Δ) :
    Reapable s := by
  induction h
  all_goals first
    | exact Reapable.src rfl
    | exact Reapable.src (by simp only [Stmt.src]; assumption)
    | exact Reapable.src (by simp only [Stmt.src, Bool.and_eq_true]; exact ⟨by assumption, by assumption⟩)
    | (rename_i iha _; exact Reapable.seq iha)
    | (rename_i ih; exact Reapable.scope ih)
    | (rename_i ih; exact Reapable.rbind ih)
    | (rename_i ih; exact Reapable.frozen ih)
    | (rename_i ih; exact Reapable.catchR ih)
    | (rename_i ih; exact Reapable.scopeD ih)
    | (rename_i ih; exact Reapable.scopeL ih)
    | (rename_i ih; exact ih)

/-- The reap of a `dead` block `k` is a step of every such statement, at its
    redex. -/
theorem Reapable.reap {P : Prog} {m : Mem} {s : Stmt} (hr : Reapable s) {k n f : Nat} {u : Ty} {p : Val}
    (hk : m.blk k = some ⟨Ty.nest n (.dtor f u), .dead, some p⟩) (hnc : ∀ c, ¬ Sub (.cell c) p) :
    ∃ m1 s1, Step P m s (.ok m1 s1) ∧ ReapMem m m1 := by
  induction hr with
  | src hs => exact ⟨_, _, Step.reap hs hk hnc, k, n, f, u, p, hk, rfl⟩
  | seq _ ih => obtain ⟨m1, s1, h, hm⟩ := ih; exact ⟨m1, _, Step.seqL h, hm⟩
  | scope _ ih => obtain ⟨m1, s1, h, hm⟩ := ih; exact ⟨m1, _, Step.scopeIn h, hm⟩
  | rbind _ ih => obtain ⟨m1, s1, h, hm⟩ := ih; exact ⟨m1, _, Step.rbindIn h, hm⟩
  | frozen _ ih => obtain ⟨m1, s1, h, hm⟩ := ih; exact ⟨m1, _, Step.frozenIn h, hm⟩
  | catchR _ ih => obtain ⟨m1, s1, h, hm⟩ := ih; exact ⟨m1, _, Step.catchIn h, hm⟩
  | scopeD _ ih => obtain ⟨m1, s1, h, hm⟩ := ih; exact ⟨m1, _, Step.scopeDIn h, hm⟩
  | scopeL _ ih => obtain ⟨m1, s1, h, hm⟩ := ih; exact ⟨m1, _, Step.scopeLIn h, hm⟩

/-- **An orphan can always be reaped** (Agora #610): in a typed
    configuration, a `dead` block's payload holds no cell share (its type
    holds none, `MInv.blocks`), so `Step.reap` is a step of the statement, at
    its redex. -/
theorem orphan_reaps {P : Prog} {Γ : Ctx} {F : List Var} {s : Stmt} {Δ : Ctx} (ht : StmtT P Γ F s Δ)
    {m : Mem} (hi : MInv m Γ) (ho : Orphan m) : ∃ m1 s1, Step P m s (.ok m1 s1) ∧ ReapMem m m1 := by
  obtain ⟨k, n, f, u, p, hk⟩ := ho
  obtain ⟨_, _, hpay, hcell, _⟩ := hi.blocks k _ hk
  have hnc : (Ty.nest n (.dtor f u)).hasCell = false := by
    rcases hcell with h | h
    · cases h
    · exact h
  exact ht.reapable.reap hk fun c => (hpay p rfl).1.noCell_hasCell hnc

/-! ### The reaps end -/

/-- A block that holds a destructor value at its top in it (Agora #755: or a
    drained `Vec` of them): an `arc` block the marking sweep may mark, or an
    orphan. -/
def DtorBlk (B : Nat → Option Blk) (k : Nat) : Prop :=
  ∃ n f u kd p, B k = some ⟨Ty.nest n (.dtor f u), kd, some p⟩ ∧ (kd = .arc ∨ kd = .dead)

open Classical in
/-- How many such blocks there are below `n`. -/
noncomputable def dtorCount (B : Nat → Option Blk) (n : Nat) : Nat :=
  (List.range n).countP fun k => decide (DtorBlk B k)

theorem countP_le_of {l : List Nat} {p q : Nat → Bool} (h : ∀ x ∈ l, p x = true → q x = true) :
    l.countP p ≤ l.countP q := by
  induction l with
  | nil => simp
  | cons a l ih =>
    simp only [List.countP_cons]
    have ih' := ih fun x hx => h x (List.mem_cons_of_mem _ hx)
    have ha := h a (List.mem_cons_self ..)
    cases hpa : p a <;> cases hqa : q a <;> simp_all <;> omega

theorem countP_lt_of {l : List Nat} {p q : Nat → Bool} (h : ∀ x ∈ l, p x = true → q x = true)
    {a : Nat} (ha : a ∈ l) (hq : q a = true) (hp : p a = false) : l.countP p < l.countP q := by
  induction l with
  | nil => cases ha
  | cons b l ih =>
    simp only [List.countP_cons]
    have hle := countP_le_of (l := l) fun x hx => h x (List.mem_cons_of_mem _ hx)
    have hb := h b (List.mem_cons_self ..)
    rcases List.mem_cons.mp ha with rfl | ha'
    · simp only [hq, hp]; simp; omega
    · have := ih (fun x hx => h x (List.mem_cons_of_mem _ hx)) ha'
      cases hpb : p b <;> cases hqb : q b <;> simp_all <;> omega

/-- The marking sweep makes no such block: it keeps or marks them. -/
theorem DtorBlk.of_sweepD {m : Mem} {k : Nat} (h : DtorBlk m.sweepD.blk k) : DtorBlk m.blk k := by
  obtain ⟨n, f, u, kd, p, hk, hkd⟩ := h
  rcases sweepBlkD_some hk with ⟨h0, _⟩ | ⟨bl0, h0, _, hp, he⟩
  · exact ⟨n, f, u, kd, p, h0, hkd⟩
  · obtain ⟨n', f', u', p', kd', rfl, hkd'⟩ := hp.shape h0
    exact ⟨n', f', u', kd', p', h0, hkd'⟩

theorem dtorCount_sweepD (m : Mem) : dtorCount m.sweepD.blk m.nid ≤ dtorCount m.blk m.nid := by
  unfold dtorCount
  exact countP_le_of fun k _ h => by simp only [decide_eq_true_eq] at h ⊢; exact h.of_sweepD

/-- A reap empties its orphan, and makes no such block. -/
theorem dtorCount_reap {m m1 : Mem} (hh : HeapOK m) (hr : ReapMem m m1) :
    dtorCount m1.blk m.nid < dtorCount m.blk m.nid := by
  obtain ⟨k, n, f, u, p, hk, rfl⟩ := hr
  unfold dtorCount
  have hkey : k < m.nid := hh.bkey k _ hk
  refine countP_lt_of (a := k) (fun k' _ h => ?_) (List.mem_range.mpr hkey) ?_ ?_
  · simp only [decide_eq_true_eq] at h ⊢
    obtain ⟨n', f', u', kd, p', hk', hkd⟩ := h
    by_cases he : k' = k
    · subst he; simp [upd] at hk'
    · exact ⟨n', f', u', kd, p', by simpa [upd, he] using hk', hkd⟩
  · simp only [decide_eq_true_eq]; exact ⟨n, f, u, .dead, p, hk, Or.inr rfl⟩
  · simp only [decide_eq_false_iff_not]
    rintro ⟨n', f', u', kd, p', hk', _⟩
    simp [upd] at hk'

/-- **The reaps that end a step can always be taken, and end** (Agora #610):
    from every typed configuration there is a `Settle`.  Each reap empties
    an orphan and the marking sweep after it makes no block that holds a
    destructor value at its top (it keeps or marks them): their count below
    `nid`, which neither changes, falls each round. -/
theorem settle_total {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {Γ : Ctx} {F : List Var} {s : Stmt}
    {Δ : Ctx} (ht : StmtT P Γ F s Δ) {m : Mem} (hcd : MemCodes P m) (hsc : s.codesOK P)
    (hi : Inv m Γ F s) (hc : Closed Γ s) : ∃ m' s', Settle P m s m' s' := by
  suffices h : ∀ n, ∀ (Γ : Ctx) (s : Stmt) (m : Mem), dtorCount m.blk m.nid < n → StmtT P Γ F s Δ →
      MemCodes P m → s.codesOK P → Inv m Γ F s → Closed Γ s → ∃ m' s', Settle P m s m' s' from
    h _ Γ s m (Nat.lt_succ_self _) ht hcd hsc hi hc
  intro n
  induction n with
  | zero => intro _ _ _ h; cases h
  | succ n ih =>
    intro Γ s m hn ht hcd hsc hi hc
    by_cases ho : Orphan m
    · obtain ⟨m1, s1, hst, hrm⟩ := orphan_reaps ht hi.toMInv ho
      obtain ⟨Γ', ht', hi', hk⟩ := preservation hP ht hcd hi hst
      obtain ⟨hcd', hsc'⟩ := (codes_step hPc hst hcd hcd.blk.1 hsc).1 _ _ rfl
      have hnid : m1.nid = m.nid := by obtain ⟨_, _, _, _, _, _, rfl⟩ := hrm; rfl
      have hlt : dtorCount m1.sweepD.blk m1.sweepD.nid < n := by
        have h1 := dtorCount_sweepD m1
        have h2 := dtorCount_reap hi.heap hrm
        rw [Mem.sweepD_nid, hnid] at *
        omega
      obtain ⟨m', s', hse⟩ := ih Γ' s1 m1.sweepD hlt ht' hcd'.sweepD hsc' hi'.sweepD (hc.step hk)
      exact ⟨m', s', Settle.reap hst hrm hse⟩
    · exact ⟨m, s, Settle.done ho⟩

/-- **Every step of a typed configuration is one of a run**: the reaps
    after it can be taken (`settle_total`), so `Steps` reaches what follows
    it. -/
theorem steps_step {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {Γ : Ctx} {F : List Var} {s : Stmt}
    {Δ : Ctx} (ht : StmtT P Γ F s Δ) {m : Mem} (hcd : MemCodes P m) (hsc : s.codesOK P)
    (hi : Inv m Γ F s) (hc : Closed Γ s) {m1 : Mem} {s1 : Stmt} (hst : Step P m s (.ok m1 s1)) :
    ∃ m' s', Steps P m s (.ok m' s') ∧ Settle P m1.sweepD s1 m' s' := by
  obtain ⟨Γ', ht', hi', hk⟩ := preservation hP ht hcd hi hst
  obtain ⟨hcd', hsc'⟩ := (codes_step hPc hst hcd hcd.blk.1 hsc).1 _ _ rfl
  obtain ⟨m', s', hse⟩ := settle_total hP hPc ht' hcd'.sweepD hsc' hi'.sweepD (hc.step hk)
  exact ⟨m', s', Steps.step hst hse Steps.refl, hse⟩

/-- **A reached configuration that is not finished steps, and not by a
    reap** (Agora #610): no store a run from the empty store reaches has an
    orphan (`no_orphan`), so no step from it is `Step.reap`'s, which needs
    one: `memory_safe`'s progress is not the reap's. -/
theorem progress_no_reap {P : Prog} (hP : ProgOK P) (hPc : ProgCodes P) {s : Stmt} {Δ : Ctx}
    (ht : StmtT P (fun _ => none) [] s Δ) (hs : s.src = true) (hsc : s.codesOK P) {nv : Nat}
    (hv : ∀ v ∈ s.vars, v < nv) {m' : Mem} {s' : Stmt} (hr : Steps P (emptyMem nv) s (.ok m' s')) :
    s' = .skip ∨ Blocked m' s' ∨ ∃ r, Step P m' s' r ∧ ∀ m1, ¬ ReapMem m' m1 := by
  obtain ⟨Γ', ht', hi', _, hcd', _⟩ :=
    reach_ok hP hPc ht (codes_empty P nv) hsc (inv_empty hs hv) (closed_empty s) hr
  have hno : ¬ Orphan m' := no_orphan hr
  rcases progress' hP ht' hcd' hi' with h | h | ⟨r, hr'⟩
  · exact Or.inl h
  · exact Or.inr (Or.inl h)
  · exact Or.inr (Or.inr ⟨r, hr', fun m1 ⟨k, n, f, u, p, hk, _⟩ => hno ⟨k, n, f, u, p, hk⟩⟩)

/-- A store with an orphan settles only by a reap first: the thread's next
    step is the reap. -/
theorem settle_reaps {P : Prog} {m m' : Mem} {s s' : Stmt} (h : Settle P m s m' s') (ho : Orphan m) :
    ∃ m1 s1, Step P m s (.ok m1 s1) ∧ ReapMem m m1 := by
  cases h with
  | done hn => exact absurd ho hn
  | reap hst hrm _ => exact ⟨_, _, hst, hrm⟩

end A2

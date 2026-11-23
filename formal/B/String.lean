import B.Vec

/-!
# B2: the raw core of `String` (AGORA-970)

A `String` is a `Vec u` (`stdlib/core/string.nu`: `__sbuf` views the same
control block) with one more invariant, the NUL-terminator discipline.
There is always room past the length (`len < cap`), and the byte at `len`
is 0, so `string_data` hands C a terminated buffer. The model here covers:

* `_string_seal`, both paths: the fast store when there is room, and
  otherwise `_vec_reserve_more` by one and then the store;
* `string_push_bytes`, both paths: the fast copy with two stores when the
  buffer already holds the bytes and the NUL, and otherwise
  `_vec_reserve_more` by `n + 1`, the `memcpy`, `vec_set_len` and the seal;
* `string_data`'s reading: every byte of the string, then the NUL, all
  inside one live block.

The bytes appended come from a pointer into another block (`* u src`).
The checker refuses `( string_push_str s ( string_data s ) )` (probe
`push_own_view`), since
the push may move `s`'s buffer and ends views of it. So the theorem asks
that the source block is not the string's own. It then shows that the
source block is never written or freed and that its bytes arrive whole.
-/

namespace B

open A1 (upd)

/-- The string `v` on `h` holds the bytes `bs`, terminated: `len < cap` and
    the cell at `len` is 0. -/
def SRep (h : Heap Nat) (v : RVec) (bs : List Nat) : Prop :=
  Rep h v bs ∧ v.len < v.cap ∧ ∃ d, v.data = some d ∧ h.cell d v.len = some 0

/-- `_string_seal`: the NUL at `len`, after growing by one when full. -/
def strSeal (h : Heap Nat) (v : RVec) : Option (Heap Nat × RVec) :=
  match (if v.len < v.cap then some (h, v) else growTo h v (v.len + 1)) with
  | none => none
  | some (h1, v1) =>
    match v1.data with
    | none => none
    | some d => (h1.store d v1.len 0).map fun h2 => (h2, v1)

/-- What a growth leaves for the string code: the list, room, the length,
    a buffer that is the old one or the heap's next fresh id, and every
    other block below `nid` as it was. -/
theorem grow_frame {h : Heap Nat} {v : RVec} {bs : List Nat} {need : Nat} (hw : h.WF)
    (hr : Rep h v bs) :
    ∃ h1 v1, (if need ≤ v.cap then some (h, v) else growTo h v need) = some (h1, v1) ∧
      Rep h1 v1 bs ∧ h1.WF ∧ need ≤ v1.cap ∧ v1.len = v.len ∧ h.nid ≤ h1.nid ∧
      (v1.data = v.data ∨ v1.data = some h.nid) ∧
      ∀ b, b < h.nid → v.data ≠ some b → h1.cell b = h.cell b ∧ h1.live b = h.live b ∧
        h1.size b = h.size b := by
  by_cases hf : need ≤ v.cap
  · rw [ite_eq_left hf]
    exact ⟨h, v, rfl, hr, hw, hf, rfl, Nat.le_refl _, Or.inl rfl, fun _ _ _ => ⟨rfl, rfl, rfl⟩⟩
  · rw [ite_eq_right hf]
    obtain ⟨h1, v1, he, hr1, hw1, hroom, hlen, hbuf⟩ := growTo_ok (need := need) hw hr
    refine ⟨h1, v1, he, hr1, hw1, hroom, hlen, ?_, ?_, fun b hb hne => ?_⟩
    · rcases hbuf with ⟨rfl, rfl⟩ | ⟨_, hn, _, _⟩
      · exact Nat.le_refl _
      · omega
    · rcases hbuf with ⟨rfl, rfl⟩ | ⟨hd, _, _, _⟩
      · exact Or.inl rfl
      · exact Or.inr hd
    · rcases hbuf with ⟨rfl, rfl⟩ | ⟨_, _, hlv, hfr⟩
      · exact ⟨rfl, rfl, rfl⟩
      · refine ⟨(hfr b hb hne).1, ?_, (hfr b hb hne).2⟩
        rw [hlv]
        have hbn : b ≠ h.nid := by omega
        cases hd : v.data with
        | none => simp only [upd, ite_eq_right hbn]
        | some d =>
          have hbd : b ≠ d := fun e => hne (by rw [hd, e])
          simp only [upd, ite_eq_right hbn, ite_eq_right hbd]

/-- `_string_seal` leaves the string terminated, the bytes as they were,
    and every block below `nid` that is not the string's own as it was. -/
theorem strSeal_ok {h : Heap Nat} {v : RVec} {bs : List Nat} (hw : h.WF) (hr : Rep h v bs) :
    ∃ h' v', strSeal h v = some (h', v') ∧ SRep h' v' bs ∧ h'.WF ∧ h.nid ≤ h'.nid ∧
      (v'.data = v.data ∨ v'.data = some h.nid) ∧
      ∀ b, b < h.nid → v.data ≠ some b → h'.cell b = h.cell b ∧ h'.live b = h.live b ∧
        h'.size b = h.size b := by
  obtain ⟨h1, v1, he, hr1, hw1, hroom, hlen, hnid, hbuf, hfr⟩ := grow_frame (need := v.len + 1) hw hr
  have hl1 : v1.len = bs.length := hr1.1
  have he' : (if v.len < v.cap then some (h, v) else growTo h v (v.len + 1)) = some (h1, v1) := by
    by_cases hf : v.len < v.cap
    · rw [ite_eq_left hf]; rw [ite_eq_left (show v.len + 1 ≤ v.cap by omega)] at he; exact he
    · rw [ite_eq_right hf]; rw [ite_eq_right (show ¬ v.len + 1 ≤ v.cap by omega)] at he; exact he
  cases hd1 : v1.data with
  | none => have := rep_none hr1 hd1; omega
  | some d =>
    obtain ⟨hld, hsz, hcell⟩ := rep_some hr1 hd1
    have hin : h1.live d = true ∧ v1.len < h1.size d := ⟨hld, by omega⟩
    refine ⟨{ h1 with cell := upd h1.cell d (upd (h1.cell d) v1.len (some 0)) }, v1, ?_,
      ⟨⟨hl1, hr1.2.1, ?_⟩, by omega, d, hd1, ?_⟩, hw1, hnid, hbuf, ?_⟩
    · unfold strSeal; rw [he']; simp only [hd1, Heap.store, hin, and_self, ↓reduceIte, Option.map_some]
    · simp only [hd1]
      refine ⟨hld, hsz, fun i hi => ?_⟩
      show (upd h1.cell d (upd (h1.cell d) v1.len (some 0))) d i = _
      simp only [upd, ↓reduceIte]; rw [ite_eq_right (by omega)]; exact hcell i hi
    · show (upd h1.cell d (upd (h1.cell d) v1.len (some 0))) d v1.len = some 0
      simp [upd]
    · intro b hb hne
      have hbd : b ≠ d := by
        intro e; subst e
        rcases hbuf with hb' | hb'
        · exact hne (by rw [← hb', hd1])
        · rw [hd1] at hb'; injection hb'; omega
      obtain ⟨hc, hl, hs⟩ := hfr b hb hne
      refine ⟨?_, hl, hs⟩
      show (upd h1.cell d _) b = h.cell b
      simp only [upd, ite_eq_right hbd]; exact hc

/-- `string_push_bytes str src n`, `src` at cell `so` of block `sb`. The fast
    path applies when the buffer already holds the bytes and the NUL: the
    copy, the length, the NUL. Otherwise `_vec_reserve_more` by `n + 1`,
    the copy, `vec_set_len`, then `_string_seal`. -/
def pushBytes (h : Heap Nat) (v : RVec) (sb so n : Nat) : Option (Heap Nat × RVec) :=
  if n > 0 ∧ v.cap > v.len + n then
    match v.data with
    | none => none
    | some d =>
      match copyAt h sb so d v.len n with
      | none => none
      | some h1 => (h1.store d (v.len + n) 0).map fun h2 => (h2, { v with len := v.len + n })
  else
    match (if n > 0 then (if v.len + (n + 1) ≤ v.cap then some (h, v) else growTo h v (v.len + (n + 1)))
           else some (h, v)) with
    | none => none
    | some (h1, v1) =>
      match (if n > 0 then
               (match v1.data with
                | none => none
                | some d => (copyAt h1 sb so d v1.len n).map fun h2 => (h2, { v1 with len := v1.len + n }))
             else some (h1, v1)) with
      | none => none
      | some (h2, v2) => strSeal h2 v2

/-- The bytes `src` at `[so, so + n)` of a live block `sb` that is not the
    string's own are appended whole, and the string stays terminated.
    `sb` is never written or freed, so the caller's source is intact. -/
theorem pushBytes_ok {h : Heap Nat} {v : RVec} {bs src : List Nat} {sb so : Nat} (hw : h.WF)
    (hr : SRep h v bs) (hsb : h.live sb = true) (hne : v.data ≠ some sb)
    (hsz : so + src.length ≤ h.size sb) (hsc : ∀ i (hi : i < src.length), h.cell sb (so + i) = some src[i]) :
    ∃ h' v', pushBytes h v sb so src.length = some (h', v') ∧ SRep h' v' (bs ++ src) ∧ h'.WF ∧
      h'.live sb = true ∧ ∀ i (hi : i < src.length), h'.cell sb (so + i) = some src[i] := by
  obtain ⟨hr0, hroom0, d0, hd0, hnul0⟩ := hr
  have hl : v.len = bs.length := hr0.1
  have hsbn : sb < h.nid := by
    rcases Nat.lt_or_ge sb h.nid with e | e
    · exact e
    · rw [hw sb e] at hsb; exact absurd hsb (by simp)
  obtain ⟨hld0, hsz0, hcell0⟩ := rep_some hr0 hd0
  have hsbd0 : sb ≠ d0 := fun e => hne (by rw [hd0, e])
  by_cases hfast : src.length > 0 ∧ v.cap > v.len + src.length
  · -- the fast path: copy, length, NUL, all inside the room the buffer has
    obtain ⟨h1, hc1, hlv1, hsz1, hn1, hoth1, hcell1⟩ := copyAt_ok (o := so) (p := v.len) hsbd0 hsb hld0
      src.length hsz (by rw [hsz0]; omega) (fun k hk => by rw [hsc k hk]; rfl)
    have hin : h1.live d0 = true ∧ v.len + src.length < h1.size d0 :=
      ⟨by rw [hlv1]; exact hld0, by rw [hsz1, hsz0]; omega⟩
    refine ⟨{ h1 with cell := upd h1.cell d0 (upd (h1.cell d0) (v.len + src.length) (some 0)) },
      { v with len := v.len + src.length }, ?_, ⟨⟨by simp; omega, by show v.len + src.length ≤ v.cap; omega, ?_⟩,
      by show v.len + src.length < v.cap; omega, d0, hd0, ?_⟩, ?_, ?_, ?_⟩
    · unfold pushBytes
      rw [ite_eq_left hfast]
      simp only [hd0, hc1, Heap.store, hin, and_self, ↓reduceIte, Option.map_some]
    · simp only [hd0]
      refine ⟨by rw [hlv1]; exact hld0, by rw [hsz1]; exact hsz0, fun i hi => ?_⟩
      show (upd h1.cell d0 _) d0 i = _
      simp only [upd, ↓reduceIte]
      simp at hi
      rw [ite_eq_right (by omega), hcell1 i]
      by_cases hi1 : i < bs.length
      · rw [ite_eq_right (by omega), hcell0 i hi1, List.getElem_append_left hi1]
      · rw [ite_eq_left (by omega), hsc (i - v.len) (by omega), List.getElem_append_right (by omega)]
        simp only [hl]
    · show (upd h1.cell d0 _) d0 (v.len + src.length) = some 0
      simp [upd]
    · intro b hb; show h1.live b = false; rw [hlv1]; exact hw b (by rw [← hn1]; exact hb)
    · show h1.live sb = true; rw [hlv1]; exact hsb
    · intro i hi
      show (upd h1.cell d0 _) sb (so + i) = _
      simp only [upd, ite_eq_right hsbd0]
      rw [hoth1 sb hsbd0, hsc i hi]
  · -- the slow path
    have hn0 : src.length = 0 ∨ src.length > 0 := by omega
    rcases hn0 with hn0 | hpos
    · have : src = [] := List.eq_nil_of_length_eq_zero hn0
      subst this
      obtain ⟨h2, v2, hs, hr2, hw2, hn2, hbuf2, hfr2⟩ := strSeal_ok hw hr0
      refine ⟨h2, v2, ?_, by simpa using hr2, hw2, (hfr2 sb hsbn hne).2.1 ▸ hsb, fun i hi => by simp at hi⟩
      unfold pushBytes
      rw [ite_eq_right hfast]
      simp only [List.length_nil, Nat.lt_irrefl, ↓reduceIte, gt_iff_lt]
      exact hs
    · obtain ⟨h1, v1, he1, hr1, hw1, hroom1, hlen1, hnid1, hbuf1, hfr1⟩ :=
        grow_frame (need := v.len + (src.length + 1)) hw hr0
      have hl1 : v1.len = bs.length := hr1.1
      cases hd1 : v1.data with
      | none => have := rep_none hr1 hd1; omega
      | some d =>
        obtain ⟨hld, hszd, hcell⟩ := rep_some hr1 hd1
        have hsbd : sb ≠ d := by
          intro e; subst e
          rcases hbuf1 with hb' | hb'
          · exact hne (by rw [← hb', hd1])
          · rw [hd1] at hb'; injection hb'; omega
        obtain ⟨hl1sb, hl1sb', hs1sb⟩ : h1.cell sb = h.cell sb ∧ h1.live sb = h.live sb ∧
            h1.size sb = h.size sb := hfr1 sb hsbn hne
        obtain ⟨h2, hc2, hlv2, hsz2, hn2, hoth2, hcell2⟩ := copyAt_ok (o := so) (p := v1.len) hsbd
          (by rw [hl1sb']; exact hsb) hld src.length (by rw [hs1sb]; exact hsz) (by rw [hszd]; omega)
          (fun k hk => by rw [hl1sb, hsc k hk]; rfl)
        have hr2 : Rep h2 { v1 with len := v1.len + src.length } (bs ++ src) := by
          refine ⟨by simp; omega, by show v1.len + src.length ≤ v1.cap; omega, ?_⟩
          simp only [hd1]
          refine ⟨by rw [hlv2]; exact hld, by rw [hsz2]; exact hszd, fun i hi => ?_⟩
          rw [hcell2 i]
          simp at hi
          by_cases hi1 : i < bs.length
          · rw [ite_eq_right (by omega), hcell i hi1, List.getElem_append_left hi1]
          · rw [ite_eq_left (by omega), hl1sb, hsc (i - v1.len) (by omega), List.getElem_append_right (by omega)]
            simp only [hl1]
        have hw2 : h2.WF := fun b hb => by rw [hlv2]; exact hw1 b (by rw [← hn2]; exact hb)
        obtain ⟨h3, v3, hs3, hr3, hw3, hn3, hbuf3, hfr3⟩ := strSeal_ok hw2 hr2
        have hsbn2 : sb < h2.nid := by rw [hn2]; omega
        have hne2 : ({ v1 with len := v1.len + src.length } : RVec).data ≠ some sb := by
          show v1.data ≠ some sb; rw [hd1]; intro e; injection e with e; exact hsbd e.symm
        obtain ⟨hc3, hl3, _⟩ := hfr3 sb hsbn2 hne2
        refine ⟨h3, v3, ?_, hr3, hw3, ?_, ?_⟩
        · unfold pushBytes
          rw [ite_eq_right hfast]
          simp only [hpos, ↓reduceIte]
          rw [he1]
          simp only [hd1, hc2, Option.map_some]
          rw [hd1] at hs3
          exact hs3
        · rw [hl3, hlv2, hl1sb']; exact hsb
        · intro i hi
          rw [hc3, hoth2 sb hsbd, hl1sb, hsc i hi]

/-- `string_data`'s pointer, read as C reads it: every byte of the string,
    then the NUL, each one a load inside the string's live block. -/
theorem data_ok {h : Heap Nat} {v : RVec} {bs : List Nat} (hr : SRep h v bs) :
    ∃ d, v.data = some d ∧ ∀ i (hi : i < (bs ++ [0]).length), h.load d i = some (bs ++ [0])[i] := by
  obtain ⟨hr0, hroom, d, hd, hnul⟩ := hr
  obtain ⟨hld, hsz, hcell⟩ := rep_some hr0 hd
  have hl : v.len = bs.length := hr0.1
  refine ⟨d, hd, fun i hi => ?_⟩
  simp at hi
  simp only [Heap.load, hld, true_and]
  rw [ite_eq_left (by omega)]
  by_cases hib : i < bs.length
  · rw [hcell i hib, List.getElem_append_left hib]
  · have : i = v.len := by omega
    subst this
    rw [hnul, List.getElem_append_right (by omega)]; simp [hl]

end B

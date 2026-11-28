module

public import B.Vec

@[expose] public section

/-!
# B6: `Channel`'s queue (AGORA-970)

`stdlib/std/channel.nu` keeps a channel in a `Shared` block (B3): its lock,
its queue `( Vec A )` (B1) and its `closed` flag. Every operation on the
queue runs under the lock, so to the model it is one step:

* `chan_send` refuses a closed channel (`F`: the value is dropped there) and
  otherwise pushes the value to the back (`vec_push`);
* `chan_recv` / `chan_try_recv` hand back the front (`vec_remove … 0`), or
  `none` on a closed and empty channel. A blocking receive on an open,
  empty channel waits, which here is a step that does not happen yet. (The
  model covers blocking receives: `chan_try_recv`'s `none` on an open,
  empty channel, a poll that changes nothing, is not a step of it);
* `chan_close` sets the flag;
* the last handle's release (`rcbox_release`) drops the queue with what is
  still in it.

The theorem is conservation, the ownership fact a channel has to keep.
Over any run, the values the sends accepted are, in order, the values
received followed by the ones still queued. So every value that went in is
handed out exactly once, in FIFO order, or dropped with the channel at the
end: none lost, none duplicated. A refused send hands its value back to be
dropped and adds nothing. The lock and the wait (pthread / fiber parking)
are the runtime's and A3's; the queue itself is B1's `Vec`, whose
`vec_push` / `vec_remove` are proven there.
-/

namespace B

variable {A : Type}

/-- What the lock guards: the queue and the closed flag. -/
structure ChState (A : Type) where
  q : List A
  closed : Bool

/-- One operation under the lock. -/
inductive ChOp (A : Type) where
  | send (v : A)
  | recv
  | close

/-- What an operation hands out: a value received, a value a refused send
    gives back to be dropped, or nothing. -/
inductive ChOut (A : Type) where
  | got (v : A)
  | refused (v : A)
  | nothing

/-- One step: `none` when a receive must wait (open and empty). -/
def chStep (c : ChState A) : ChOp A → Option (ChState A × ChOut A)
  | .send v => if c.closed then some (c, .refused v) else some ({ c with q := c.q ++ [v] }, .nothing)
  | .recv => match c.q with
    | x :: rest => some ({ c with q := rest }, .got x)
    | [] => if c.closed then some (c, .nothing) else none
  | .close => some ({ c with closed := true }, .nothing)

/-- A run of operations that each could step, from `c`, with what each
    handed out. -/
inductive ChRun : ChState A → List (ChOp A) → ChState A → List (ChOut A) → Prop
  | nil {c : ChState A} : ChRun c [] c []
  | cons {c c1 c2 : ChState A} {o : ChOp A} {os : List (ChOp A)} {out : ChOut A} {outs : List (ChOut A)} :
      chStep c o = some (c1, out) → ChRun c1 os c2 outs → ChRun c (o :: os) c2 (out :: outs)

/-- The values the sends of a run put on the queue: a send to an open
    channel at the time. -/
def accepted : List (ChOp A) → List (ChOut A) → List A
  | .send v :: os, .nothing :: outs => v :: accepted os outs
  | _ :: os, _ :: outs => accepted os outs
  | _, _ => []

/-- The values a run's receives got. -/
def received : List (ChOut A) → List A
  | .got v :: outs => v :: received outs
  | _ :: outs => received outs
  | [] => []

/-- The values refused sends handed back to be dropped. -/
def refusedVals : List (ChOut A) → List A
  | .refused v :: outs => v :: refusedVals outs
  | _ :: outs => refusedVals outs
  | [] => []

/-- The values a run's sends offered. -/
def offered : List (ChOp A) → List A
  | .send v :: os => v :: offered os
  | _ :: os => offered os
  | [] => []

/-- Conservation: what was queued, then accepted, comes out as what was
    received, then what is still queued, in order. -/
theorem conservation :
    ∀ {c c' : ChState A} {os : List (ChOp A)} {outs : List (ChOut A)}, ChRun c os c' outs →
      c.q ++ accepted os outs = received outs ++ c'.q := by
  intro c c' os outs h
  induction h with
  | nil => simp [accepted, received]
  | @cons c c1 c2 o os out outs hs hr ih =>
    cases o with
    | send v =>
      by_cases hc : c.closed
      · simp [chStep, hc] at hs; obtain ⟨rfl, rfl⟩ := hs
        simpa [accepted, received] using ih
      · simp [chStep, hc] at hs; obtain ⟨rfl, rfl⟩ := hs
        simp only [accepted, received]
        rw [← ih]; simp
    | recv =>
      cases hq : c.q with
      | cons x rest =>
        simp [chStep, hq] at hs; obtain ⟨rfl, rfl⟩ := hs
        simp only [received]
        cases os <;> cases outs <;> simp_all [accepted]
      | nil =>
        by_cases hc : c.closed
        · simp [chStep, hq, hc] at hs; obtain ⟨rfl, rfl⟩ := hs
          cases os <;> cases outs <;> simp_all [accepted, received]
        · simp [chStep, hq, hc] at hs
    | close =>
      simp [chStep] at hs; obtain ⟨rfl, rfl⟩ := hs
      cases os <;> cases outs <;> simp_all [accepted, received]

/-- Every value offered is accepted or refused (handed back to be dropped). -/
theorem offered_split :
    ∀ {c c' : ChState A} {os : List (ChOp A)} {outs : List (ChOut A)}, ChRun c os c' outs →
      (offered os).length = (accepted os outs).length + (refusedVals outs).length := by
  intro c c' os outs h
  induction h with
  | nil => simp [offered, accepted, refusedVals]
  | @cons c c1 c2 o os out outs hs hr ih =>
    cases o with
    | send v =>
      by_cases hc : c.closed
      · simp [chStep, hc] at hs; obtain ⟨rfl, rfl⟩ := hs
        simp only [offered, accepted, refusedVals, List.length_cons]; omega
      · simp [chStep, hc] at hs; obtain ⟨rfl, rfl⟩ := hs
        simp only [offered, accepted, refusedVals, List.length_cons]; omega
    | recv =>
      cases hq : c.q with
      | cons x rest =>
        simp [chStep, hq] at hs; obtain ⟨rfl, rfl⟩ := hs
        simp only [offered, refusedVals]; cases os <;> cases outs <;> simp_all [accepted]
      | nil =>
        by_cases hc : c.closed
        · simp [chStep, hq, hc] at hs; obtain ⟨rfl, rfl⟩ := hs
          simp only [offered, refusedVals]; cases os <;> cases outs <;> simp_all [accepted]
        · simp [chStep, hq, hc] at hs
    | close =>
      simp [chStep] at hs; obtain ⟨rfl, rfl⟩ := hs
      simp only [offered, refusedVals]; cases os <;> cases outs <;> simp_all [accepted]

/-- From a fresh channel (`chan_new`: empty, open), what the sends
    accepted is what was received followed by what the channel still holds,
    which its last release drops. -/
theorem fresh_conservation {os : List (ChOp A)} {c' : ChState A} {outs : List (ChOut A)}
    (h : ChRun ⟨[], false⟩ os c' outs) : accepted os outs = received outs ++ c'.q := by
  simpa using conservation h

/-- A receive on a channel that holds something always steps, and gets
    the front. On a closed, empty one it steps with nothing. It waits only
    on an open, empty channel. -/
theorem recv_steps (c : ChState A) :
    (∀ x rest, c.q = x :: rest → chStep c .recv = some ({ c with q := rest }, .got x)) ∧
    (c.q = [] → c.closed = true → chStep c .recv = some (c, .nothing)) ∧
    (chStep c .recv = none ↔ c.q = [] ∧ c.closed = false) := by
  refine ⟨fun x rest h => by simp [chStep, h], fun h hc => by simp [chStep, h, hc], ?_⟩
  cases hq : c.q with
  | cons x rest => simp [chStep, hq]
  | nil => cases hc : c.closed <;> simp [chStep, hq, hc]

end B

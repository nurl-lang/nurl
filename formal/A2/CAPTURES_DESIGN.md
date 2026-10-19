# A2-6a — by-name closure captures: design state

Status: the memory-safety invariant has been strengthened for captures and
builds green through `A2.CallInv` (the whole call machinery). `A2.Closure`
(the closure/`dyn` *package-call* preservation) is the remaining file.

## What is settled and proven (green through `CallInv`)

1. **A binding held by name is live and holds nothing.** `DepsNamed` now
   requires, for every by-name dep `⟨r, .name b t⟩`, that `Γ r` is live,
   owns its slot, has `held = []`, type `t` with `t.holdsView = false`, and
   allows `b` (`b = .none ∨ b ≠ .replace ∧ canDo`). Consequence: no change to
   another binding can dangle a named binding, and moving/replacing/freeing a
   binding ends everything that names it. Threaded through
   `Frame → Rhs → Steps → TypingFacts → Preservation → Wf → NameWf →
   Rename → Call → CallMem → CallInv`.

2. **`ownHeld`**: an owned value of a view-free type holds nothing, so a
   view-free vector `push`/`inout` adds nothing to track.

3. **`Entry.fixed`** = borrowed param, or a view-free non-`replace` `inout`
   param. `EntryWeaker` preserves fixed entries (live/held/own-slot path);
   `AbsOK` carries "a fixed `inout` param holds nothing".

4. **nurlc already closes the aliasing holes.** Probes (`c(c)`, `h(use,grow)`,
   `f(use grow)`, `use grow`) are all rejected by nurlc with the §2.11
   route-aliasing error. The distinction nurlc enforces, and that the formal
   `NamesFree` mirrors, is **reader-vs-writer**: a binding mutated by name may
   be *written* by name from several arguments (safe — every access re-reads
   the binding, so a realloc is seen), but may not be *read by handle* (a
   view) beside such a writer (the view goes stale). `NamesFree`'s last
   clause `d'.kind.bound ≠ .none` is exactly this.

## The one real design decision for `Closure.lean`

The opened (implementation) call binds the captures as trailing
`inp`/`inout` arguments: `args = m.nv :: zs ++ cs.map (·.1)`,
`fn.params = (.inp, te) :: sig.params.tail ++ cs.map (·.2)` (from
`Implements`/`pkg_code`). The environment receiver `envE` genuinely *names*
its captures (the package's `Ec.held` carries `capDeps cs`, and by-handle
captured closures carry names too — so `envE` cannot simply drop names).

Therefore a mutated (`inout`) capture passed as an argument is *reached by
name* by the receiver argument. `CallT`'s current moves-condition

```
args[i] ∉ roots (argE Γ args[j]).vdeps        -- blanket: memory OR name
```

rejects this. The **correct refinement** (sound, and less conservative — it
even admits valid programs the blanket rule rejects) is to police only the
aliasing that is actually unsafe:

```
args[i] ∉ roots (memDeps (argE Γ args[j]).vdeps)                 -- always
∧ (fn.params[i].1 = .sink →
     args[i] ∉ roots (nameDeps (argE Γ args[j]).vdeps))          -- sink only
```

Rationale:
- **memory reach** (view/inner/self) to any moved arg is always unsafe
  (stale handle on move/realloc) — forbid always;
- **by-name reach** to an `inout` arg is safe (the binding survives; a
  realloc is seen through the name) — allow, and let `NamesFree` govern it
  (writers-only, no reader-beside-writer);
- **by-name reach** to a `sink` arg is unsafe (the binding is freed) — forbid.
  (`NamesFree`'s `d.root ∉ args` already catches *write*-names to a direct
  arg; the explicit `sink` clause catches *read*-names.)

In a proof assistant this cannot introduce a hole: it only compiles once it
is sound.

### Remaining mechanization (in order)
1. Apply the moves-condition refinement to `CallT` (Typing) and `CallH.arg`
   (Call), then repair `CallT.names`/`CallH` naming lemmas: a by-name dep may
   now point to an `inout` moved arg (which survives), so the `movedArgs`
   exclusion (`hfree`) must be split into sink (fully excluded) vs inout
   (name-reachable, still valid because live).
2. `open_pkg`: build the opened `CallT` over `m.nv :: zs ++ cs.map (·.1)`;
   per-capture `paramOK` and moves/`NamesFree` come from `pkg_caps`
   (live/own/view-free/`canDo`) + `PkgsOK` (nodup, no capture reached from
   another) + `FnOK` (an `inout` param is a `.vec`).
3. `cloProgress`/`cloCase`: the `BindParams` step already binds
   `m.nv :: zs ++ cs.map (·.1)`; align the `callStmt`/frame reasoning.
4. `weaker_open`: the opened call and the package call kill the *same*
   capture roots (via `envE_names`), so relate the two `killNames` with the
   order-independent `killAll`/`canon_quiet` machinery already in `Rename`.

## Scope note (measured, not yet mechanized)

The moves-condition refinement is correct but its ripple is **wide**, because
admitting a by-name reach to an `inout` moved argument changes a core frame
invariant: a by-name dependency root may now legitimately *be* an `inout`
moved argument (it survives the call, so naming it stays valid). Concretely
these all shift from "no moved arg is reached at all" to "no moved arg is
reached *by memory*, and a `sink` is reached by nothing":

- `Call.moving_root` → memory-only; add `Call.sink_root` (full) for sinks.
- `Call.notRen_root`, `Call.frame_root`, `frame_sat`, `argNames_root`,
  `sOK.N_out`/`Rroot`, and `NameWf.CallT.names`'s `movedArgs` exclusion must
  split into memory (all moved args) vs by-name (sinks only, via `sinkArgs`).
- `Rename` needs `roots_liftE_ρ_mem` / `roots_liftE_ρ_name` (memory/name
  variants of `roots_liftE_ρ`) — drafted and type-checked in isolation.

Done in a focused pass this is routine (every step is Lean-checked, so no
unsound shortcut is possible), but it touches the whole frame/naming layer of
`Call.lean`; it was reverted here to keep the tree green through `CallInv`
rather than commit a half-applied refinement. The `NameWf`/`Rename` pieces
(`sinkArgs`, `mem_sinkArgs`, `roots_liftE_ρ_mem`, `roots_liftE_ρ_name`, the
`CallT.names` sink-split) were proven and are the template for the rest.

## Why cs-as-arguments is the faithful model (checked against nurlc)

nurlc (`compiler/nurlc.nu`) compiles a closure as a `{fn-ptr, env-ptr}`
struct; a by-name / `inout` capture is **the caller's binding passed by
address, held in the env** (see nurlc.nu:720, 765, 4706, 6807). In the
formal big-step/substitution semantics the equivalent of "dereference the
captured binding's address at call time" is exactly binding that binding's
current value as a parameter — i.e. the step's `m.nv :: zs ++ cs.map (·.1)`.
So the opened call genuinely passes the captures as trailing args, the
receiver (env) genuinely names them, and the `CallT` moves-condition
refinement (memory-aliasing always, by-name only for `sink`) is the correct
and necessary design — there is no env-only shortcut.

## The one structural consequence left to mechanize: `RSetup.N_out`

At the opened call the captures are **both** direct arguments (`ρ`-images:
callee params) **and** by-name roots of the receiver. So the frame
invariant `RSetup.OK.N_out` — "every `N` (by-name) root is not a `ρ`-image
and lives in the frame `Φ`" — no longer holds as stated: a by-name root may
be an `inout` moved argument, which is a callee parameter. `N_out` must be
generalized to a disjunction (a by-name root is either a frame binding, as
now, or an `inout` argument the call renames), and `canon_names` / `Φnamed`
/ `sOK` updated to match. This is the deepest remaining edit; everything
else (`open_pkg` building the extended `CallT`, `cloCase` aligning the
`BindParams` step, `weaker_open`'s equal-kill `killNames`) builds on it.
This is the point to resume from — the invariant change is the keystone, and
the `sinkArgs` / `roots_liftE_ρ_mem` / `roots_liftE_ρ_name` / `moving_root`-
`sink_root` lemmas are already worked out as its scaffolding.

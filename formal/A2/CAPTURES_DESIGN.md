# A2-6a — by-name closure captures: design state

## Status

`lake build` is green through `A2.Soundness`. It has no `sorry`, and
`memory_safe`, `soundness`, `preservation`, `progress'` and `no_leak_end`
rest only on Lean's standard axioms. The proof covers **fragment (II)**,
described below. nurlc accepts more than (II): it also lets a closure that
grows a binding be handed to a function. That case is **(I)**, not yet
proven, and the last section plans it.

## Fragment (II): what the typing admits

A capture is `⟨v, .name b t⟩` in the package's `held`. The package names `v`
and does not hold a view of it. Read-only captures (`b = .none`) and
by-handle captures are unrestricted. A closure that may change a binding
by name (an `inout` capture with `b ≠ .none`, a *writer*):

- is called where it is (`callc`);
- is not handed to a call. `NoWriters` (Typing) applies to the `letcall`
  arguments and to the `callc` arguments after the receiver: any argument
  the callee could reach through holds only readers;
- is not captured by another closure. `pack`'s environment is
  writer-free;
- is not held by a borrowed binding. `rbind` requires every dependency
  of the binding to have bound `.none`.

The call through the package itself still checks `NamesFree`. A changed
capture is not lent (`∉ F`), is not an argument, and other arguments reach
it only by writers. With `NoWriters` on the other arguments, that means only
the package reaches it.

## How a call through a package runs (Semantics, `Step.callc`)

The environment is bound as a fresh borrowed parameter `m.nv`. The code is
called on `m.nv :: zs ++ cs.map (·.1)` with parameters
`(.inp, te) :: sig.params.tail ++ cs.map (·.2)` (`Implements`). So each
capture is an argument of its own. This matches nurlc: a by-name capture is
the caller's binding, passed by address in the closure's environment. At
call time, dereferencing that address is the same as binding the binding's
current value as a parameter.

## The proof of the package call (`Closure.lean`)

- `envE`: the receiver's entry. It keeps only the *readers* of what the
  package depends on and holds, so it never reaches a capture the package
  may change (`envE_cap_out`).
- `pkg_cap`, `pkg_cap_mutName`, `pkg_cap_mut`: a capture is live, owned,
  view-free and holds nothing. A capture the package may change is one of
  the names the call through the package changes (`mutNames`), so
  `NamesFree` applies to it.
- `open_pkg`: the opened call is well-typed (`CallT`) with the captures as
  arguments. Its arguments are writer-free (`NoWriters`), and the roots
  the environment depends on are held still for the call.
- `weaker_open`: once the environment is dropped, the context after the
  opened call says no less than the context after the call through the
  package. The reasons:
  - The captures add nothing to what the call lends, holds or stores
    (`callRes_append`, `outHeld_append`, `heldOfArgs_append_nil`). The
    interface's summary indices all point below the captures (`lendable`).
  - Past the receiver, the arguments relate as before (`post_rel`).
  - The captures relate by `callPostAux_caps` and `PostRel.caps`. A changed
    capture is handed back as it was. What the opened call ends through a
    capture (`capKills`), the call through the package ends too, since
    those deps are among its `mutNames`.
  - The call through the package may end more than the opened call does.
    Those extra kills never touch a borrowed parameter: its memory
    dependencies are anchored in `F`, a changed name is not in `F`, and a
    name is ended only by `replace`, which no capture allows
    (`weaker_killAll_more`).
- `cloProgress` and `cloCase`: the step and its preservation, run through
  the generic call machinery (`callH_of`, `CallH.inv`, `typedIn`) on the
  cleaned context with the environment bound.

## (I): handing a growing closure to a call (not yet proven)

nurlc accepts this program; fragment (II) rejects it:

```
@ run ( @ v ) g → v { ( g ) }
… : ( @ v ) grow \ → v { ( vec_push [i] v k ) … }
  ( run grow )
```

nurlc's §2.11 route rule (h274–h280) only forbids *another argument* that
reaches `v` beside the growing closure, and passing `v` `inout` beside a
closure that captures it.

Probing (I) in nurlc turned up a memory-safety hole of this family, now
closed and gated as `tools/fuzz/holes/h285`: a closure holding a view of a
`Vec` it captured across a call to one of its own closure *parameters*,
where the caller hands that parameter a closure that re-enters the closure
and grows the `Vec` (ASan: heap-use-after-free). nurlc carried the effect of
running a *captured* closure (h278) but not of running a *parameter*, whose
captures are the caller's to choose. Closed additively: a call to an opaque
closure parameter inside a closure body ends the views of every binding the
closure captured by reference (`bck_opaque_param_run`). The proof fragment
(I) below is the formal counterpart — what justifies admitting the safe
higher-order programs this conservative rule still rejects.

### What (I) needs in the proof, and why it is one coordinated change

In (II) the only call-side restriction is `NoWriters`: a writer closure is
never a call argument. Dropping it means the arguments' names `N` (and so
the frozen set `A = allKinds R ++ N` that `liftE` appends to every lifted
callee binding) may contain writers. Most of the renaming lemma survives
that as is: a writer's target `r` is a caller binding no callee binding
reaches in memory (`N_mut`: `r ∉ R`), a name is ended only by `replace`
(`kills_isName`), so the extra kills the renamed call makes are quiet on the
callee's lifted bindings and, by `N_mut`, on the frame. Two things do not
survive, and both were found by the build, not by reading:

- **The `pack` premise does not commute with renaming.** `liftE` broadcasts
  `A` into every view-holding owned binding, so a closure made inside a
  callee that received a writer argument is lifted holding that writer —
  and the writer-free `pack` premise cannot be re-proven for it. Narrowing
  the broadcast to memory and readers is *unsound*: a call's result holds
  what its arguments hold by name (`heldOfArgs ⊇ argNames`), so when a
  closure parameter is passed on, the result legitimately holds its writer,
  which only the full broadcast can supply (the abstract callee context has
  no names on its parameters). Tried and reverted here (`Am` in
  `Rename.lean`): it breaks exactly the pass-on result and every element or
  copy derived from a receiver. The way out is to *drop* the `pack` premise:
  a closure whose environment holds a writer is treated as writing it —
  its `held` carries the name, so running it (`callc`) kills the target.
  That is h278 for free. By-name capture of a writer stays impossible
  (`CapsOK` needs `held = []`). It needs `PkgsOK`'s fourth conjunct dropped
  and `ValOK.pkg` to validate the environment through every dependency that
  is not one of the package's *own* `inout` captures (not through `readers`
  only), so `envE` keeps nested writers while still never reaching an own
  capture (`envE_cap_out`), and `reroot_valOK` carries that filter.

- **The formal h285.** Inside a closure's code, its captures are `inout`
  parameters and a closure parameter `h` is a borrowed `fn` with no names in
  the abstract context. The abstract `callc h` kills nothing, while the
  renamed one (with `h ↦ pe h`, the actual closure) kills the views of `h`'s
  targets, among them this code's own `inout` parameters when the caller
  re-enters it: a live abstract view of one survives where the renamed view
  is dead, and `PW` fails — the renaming lemma is false for the h285
  program, which the abstract typing accepts. A "no live view of an `inout`
  parameter at an opaque call" premise does not commute with renaming
  either (in `canon` the callee's `inout` parameters are owned and the
  `inout` entries are the caller's). What commutes is to make the abstract
  context *say* what an opaque closure may write: a closure-typed borrowed
  parameter carries, in `sigCtx`, a symbolic writer name for each view-free
  `inout` parameter of the function — then the abstract `callc h` and any
  call `h` is passed to kill those views and check `NamesFree` on them (so
  h285's code is rejected, and passing an `inout` parameter beside `h` is
  rejected, as nurlc does), and the lift replaces the symbolic names by the
  actual ones (`pe h`). The abstract kills a superset of what the renamed
  call kills, which is the direction `PW` allows. This needs `AbsOK`'s
  "a borrowed parameter holds nothing" to become "holds only names"
  (`hits_lift` still holds: a name is never hit), `sigCtx_names` for the
  symbolic names (an `inout` parameter owns its slot and allows its own
  bound), and `FnOK` to exclude view-holding `inout` parameters from the
  symbolic set (no closure can capture one `inout`: `CapsOK`).

With both in place the moves-condition of `CallT` may admit an `inout`
argument reached *by name* from another argument (memory reach stays
forbidden, a `sink` is reached by nothing), which `open_pkg` needs when a
`callc` argument names the package's own capture; the relaxation tried
earlier was unsound only because the abstract code could still hold a view
across the opaque call — the symbolic names close that. `NoWriters`,
`N_noW`, the `rbind` writer-free premise (already done) and the `pack`
premise then all go, and `canon_quiet` / `namesFree_lift` discharge from
`N_mut` and `kills_isName`.

Two smaller units were tried and ruled out, so the next attempt need not:
keeping `NoWriters` on `callc` arguments only (nurlc's writer-beside-writer
rejection, which would spare the moves-condition relaxation) cannot be
re-established under renaming for the same broadcast reason; and a
symbolic "holds closure `h`" reader name on closure parameters, with
`mutNames` following a name on a closure-typed binding one level into that
binding's writers (h278 in the calculus), would remove the name broadcast
altogether (`A := allKinds R`) and so the coupling — but it needs
`DepsNamed` to admit a borrowed closure as a named target and has no sound
marker for a container of closures (`holdsView`). The symbolic `inout`
sibling names above are the version that survives.

None of it changes generated code: nurlc already compiles (I). It is one
coordinated change across `Typing` (`sigCtx`, `CallT`, `pack`),
`Invariant` (`PkgsOK`, `ValOK.pkg`), `Rename` (`AbsOK`, `RSetup.OK`),
`Call`/`CallInv`, `Closure` (`envE`, `open_pkg`), `Steps`/`Stability`
(`reroot_valOK`) and the threading through `Preservation`/`Progress`; the
pieces are mutually dependent, so it lands green or not at all. Everything
above is the state at the `green-ii` tag.

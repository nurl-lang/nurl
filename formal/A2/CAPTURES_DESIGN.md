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

Probing (I) in nurlc turned up a memory-safety hole of this family, tracked
as `tools/fuzz/holes/open/h285`: a closure holding a view of a `Vec` it
captured across a call to one of its own closure *parameters*, where the
caller hands that parameter a closure that re-enters the closure and grows
the `Vec` (ASan: heap-use-after-free). nurlc carries the effect of running a
*captured* closure (h278) but not of running a *parameter*, whose captures
are the caller's to choose. Its fix is additive and identified (a call to an
opaque closure value may move its enclosing closure's by-reference captures'
buffers); the proof of (I) below is what justifies it.

Covering (I) needs the call model to follow the writer into the callee:

1. **Frozen set.** `heldFor` freezes every caller root below the base that
   the call does not move, including `v`. But the callee runs `g`, which
   changes `v`. The frozen set must leave out the roots of the call's
   `mutNames`. It is a ghost annotation, so this costs no run time.
2. **Kill at entry.** A caller binding that views `v` (a slice, say) is
   ended by the call's `killNames`. Today that happens only after the call,
   while the frame invariant still treats the binding as live during the
   callee's run. The frame the callee runs under (`callS`) should apply the
   call's name kills at entry.
3. **Lift the parameter's names.** In the callee, a closure parameter is a
   borrowed parameter (`paramE`) with no dependencies. The runtime context
   (`canon`) gives it the argument's dependencies, including the writer
   name on `v`. Then the lifted inner `callc` of `g` checks `NamesFree` on
   `v` against the lifted frozen set (1), and kills nothing new in the
   frame (2). `RSetup.OK` must carry by-name dependencies with bound
   `≠ .none` for borrowed parameters, so the `rbind` premise above becomes
   a rerooting of the writer names at the parameter's exit.
4. **Transitivity.** With 1–3 in place, `NoWriters` and the writer-free
   `pack` and `rbind` premises can be dropped. A callee can then hand `g`
   on, or capture it, under the same `NamesFree`.

Each step strictly enlarges the typing. None changes generated code: nurlc
already compiles (I).

# A2-6a — by-name closure captures: design state

## Status

`lake build` is green through `A2.Soundness`. It has no `sorry`, and
`memory_safe`, `soundness`, `preservation`, `progress'` and `no_leak_end`
rest only on Lean's standard axioms (`../check.sh`). The proof covers
**both fragments** below: (II), where a closure that changes a binding is
only called where it is, and (I), where it is handed to a call, captured,
or held by a borrowed binding — what nurlc accepts. The last section
records the design of (I) as it stands in the sources.

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

## (I): handing a growing closure to a call (proven)

nurlc accepts this program; fragment (II) alone rejected it:

```
@ run ( @ v ) g → v { ( g ) }
… : ( @ v ) grow \ → v { ( vec_push [i] v k ) … }
  ( run grow )
```

nurlc's §2.11 route rule (h274–h280) forbids *another argument* that
reaches `v` beside the growing closure, and passing `v` beside a closure
that captures it.

Probing (I) in nurlc turned up a memory-safety hole of this family, now
closed and gated as `tools/fuzz/holes/h285`: a closure holding a view of a
`Vec` it captured across a call to one of its own closure *parameters*,
where the caller hands that parameter a closure that re-enters the closure
and grows the `Vec` (ASan: heap-use-after-free). nurlc carried the effect of
running a *captured* closure (h278) but not of running a *parameter*, whose
captures are the caller's to choose. Closed additively: a call to an opaque
closure parameter inside a closure body ends the views of every binding the
closure captured by reference (`bck_opaque_param_run`). Its formal
counterpart is the symbolic names below.

### The design, as proven

One coordinated change; each piece is forced by the renaming lemma, which
lifts a callee body typed once against its own view of its parameters
(`sigCtx`) to where a call places it (`Rename.lean`), broadcasting what the
arguments held (`A = allKinds R ++ N`) into every lifted binding that may
hold it.

- **The environment of a package** (`envDeps`, `ValOK.pkg`, `PkgsOK`). A
  package's environment is valid through everything the package holds but
  its *own* change of a capture (`ownWriter`: a name whose bound is not
  `.none`, rooted at one of its `inout` captures). A closure the
  environment holds that changes some other binding stays: running the
  package runs it, so the package's `held` carries the name and `callc`
  ends what the change ends. The writer-free `pack` premise is gone;
  `reroot_envDeps` carries the filter through a borrowed parameter's exit.
  In `Closure.lean` the opened environment is `envE c Ec te cs`.

- **Symbolic names** (`symNames`, `paramE`, `Ty.hasFn`). In the callee's
  own context every parameter whose type may hold a closure (`hasFn`:
  `fn`, or an aggregate or container of one) holds, by name, each `inout`
  parameter that holds no views and is neither read-only nor replaced,
  with that parameter's bound. So running what such a parameter holds
  (`callc`), or handing it on, ends those parameters' views in the
  callee's check (h285 in the calculus: the abstract call kills what the
  renamed one may), and passing an `inout` parameter beside it is checked
  by `NamesFree`. The call replaces the symbolic names by the actual
  closure's (`RSetup.sym`, `sym_ok`/`sym_of`; `AbsOK`: a borrowed
  parameter holds exactly them; `hits_lift` under `Allowed`, since the
  targets are never replaced; `sym_quiet` for the kills after a call whose
  closure argument does not hold the argument after all).

- **The call rule** (`CallT`, `NamesFree`). An `inout` argument is reached
  by another argument, or by itself, only by a name of the parameter's
  own bound (`d.kind.bound = b ∧ b ≠ .none`), never in memory; a `sink`
  argument by nothing. `NamesFree` admits a changed binding that is an
  `inout` argument of exactly that bound, and makes every argument's name
  on a changed binding carry the same bound: the callee tells no two
  closures apart, and the broadcast `N` lifts only when its names agree
  per root. `callc` adds that no argument is a binding the package may
  change by name (the capture is handed to the code as an `inout`
  argument of its own, so it could not also be passed). Narrowing the
  broadcast instead was tried and is unsound for a result that passes a
  closure parameter on (`heldOfArgs ⊇ argNames`).

- **The call setting** (`callS`, `Call.lean`). `N` holds the arguments'
  names of the frame only (`inoutArgs` excluded); a name on an `inout`
  argument is the image of a symbolic name (`pe_names`, `argName_cases`).
  A borrowed parameter's entry holds by name only what its type can
  (`callPe`, `typedDeps`), so the abstract and the lifted entries agree
  — a value of a type without a closure holds nothing by name
  (`WFv.names_nil_fn`, `ValOK.names_nil_fn`, `ValOK.memDeps`). After a
  call, only the `sink` arguments are ended (`CallT.names`, `sunkArgs`);
  what a borrowed parameter may change by name stays bound to the end
  (`wrap_typed`, the `rbind` premise).

- **The opened package call** (`Closure.lean`). The typing lends `heldN`:
  what the run-time form holds still (`heldFor`) but what the call's
  closures may change by name (`StmtT.frozen` lends a part). The opened
  call's own kills are carried by `PostRel.caps`; `mutNames_open` relates
  them to the call through the package; `open_pkg` builds the opened
  `CallT` — the captures as `inout` arguments reached by the other
  arguments only by names of the captures' bounds, which `NamesFree` of
  the call through the package gives.

Two smaller units were tried and ruled out, so a later change need not:
keeping a writer-free rule on `callc` arguments only cannot be
re-established under renaming (the broadcast puts the same writer into the
receiver and the argument); and a symbolic "holds closure `h`" reader name
on closure parameters, with `mutNames` following a name on a closure-typed
binding one level into that binding's writers, has no sound marker for a
container of closures. The symbolic `inout` sibling names are the version
that survives.

None of it changes generated code: nurlc already compiled (I), and is
stricter than the calculus at every point above (it forbids any other
argument reaching a binding beside the closure that changes it; the
calculus admits one that changes it the same way).

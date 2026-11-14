# The reference checker's rules

What `check.py` checks on the core IR ([docs/dev/CORE_IR.md](../../docs/dev/CORE_IR.md)),
one rule a row. This is the working list for stage S2 of
[PROPOSAL_CORE_IR.md](../../docs/dev/PROPOSAL_CORE_IR.md): the rules the engine
in nurlc will transcribe, each with where docs/MEMORY.md states it. A rule
that is here is applied to every spelling: the checker never sees one.

`run.py --nurlc --all` says how many hole probes agree with their `// map:`
verdict under these rules. A probe that disagrees is a rule missing from
this list, or one written too coarsely.

## State

Per variable, at a program point:

| part | meaning |
|---|---|
| `own` | `O` owner, `P` a parameter (the caller's), `L` lent, `N` nothing to track, `M` moved, `X` moved on some paths, `U` not assigned yet, `D` released |
| `loans` | the loans the value itself needs: it is a handle or a view of those places |
| `alias` | the places it is a handle or a view of (what an effect through it reaches) |
| `held` | (path, loan): the loans held inside it, by where they sit (`name`, `*`, `#T0`, `^i` a closure's capture `i`) |
| `call` | the lend came out of a call: a copy of a handle its owner keeps, not the owner's part read in place |

Per path: `dead` (the loans ended so far), `gone` (fields taken out of their
owner), the `;` blocks armed.

A **loan** is a place and a kind:

| kind | is | ended by |
|---|---|---|
| `handle` | a copy of the handle the place holds | the place replaced or released; its elements dropped, for a loan below them |
| `view` | a pointer into the place's own buffer | the same, and the buffer moving (`realloc`) |
| `ref` | a pointer to the binding itself (a capture taken by pointer) | the binding's scope ending, or the binding moved |
| `share` | a closure's own copy of a shared handle | nothing |
| `held` | what a parameter's value holds: the caller's to say | nothing in this frame; each call puts what its argument holds in its place |

An **effect** on a place is `realloc`, `drop` (its elements), `replace` (its
value), `take` (a field or a payload moved out of where it lived: only what
was lent out of that part ends, and a closure's handle of the value around
it) or `end` (the binding). `kills_paths` is formal/A2's `Eff.kills`
lifted from bindings to places.

A **summary** per function: `res`, `lends`, `rholds`, `effects`, `stores`,
`consumes`, `elems` as in prims.py, and `invokes` (the closure arguments it
runs), `cloargs` (what it hands them of its other arguments), `detaches`
(closures another thread runs), `shares` (arguments several threads reach),
`regions` (effects inside a shared payload). Program functions are
summarised by the same analysis, to a fixpoint over the program.

## Rules

| rule | MEMORY.md | in check.py |
|---|---|---|
| A use of a value whose loan has ended is the error | §2.10 | `check_live` |
| An owner handed on by name moves; `: ~` of a name is a cursor | §2.2, §7.6 | `transfer`, `move_out` |
| A value that holds a view is read whole only while what the view points into is there | §2.10 | `read` |
| A call's arguments are frozen for its duration: its effects end no view another argument holds | §2.4 | `apply_call` |
| An `inout` argument is the callee's alone for the call: no other argument is the same binding, a part of it or a lend of it | §2.4 | `apply_call` |
| A function that hands a parameter to a callee that detaches it detaches its argument | §2.7 | `s_detaches` |
| A call's effects come before its stores; a consumed argument is moved | §2.1 | `apply_call` |
| A view-typed parameter (`s`, a slice) is a view the caller lent, never an owner | §1 | `read` |
| A borrow handed to a consumer: a part read in place is taken out of its owner; a call's lend in a temporary is copied; a binding of a call's lend is refused | §2.5, §7.6 | `apply_call`, `take_payload` |
| A field taken out of its owner is not read, nor the value handed on whole, until it is given a value again | §2.1 | `State.gone` |
| A part taken out of an `inout` parameter is a change to the caller's binding, not a hand-over of it; left taken at an exit, it is gone in the caller's binding | §2.1, §2.12 | `take_payload`, summary `gone` |
| A lend of an element given back to the same element is read before the old value goes | §2.4 | `apply_call` (`stored_back`) |
| A store replacing a place hands its old value to the binding that read that very place | §7.6 (#265) | `handover` |
| A `: ~` cursor of a binding kept by value (pushed, stored into a literal) hands the binding on: the binding is moved through it, and the cursor reads the value where it went | §7.6 | `apply_call` stores, `rvalue` (`agg`) |
| What was lent out of a temporary follows it into the binding it moves to | §1 Temporaries | `rehome` |
| `= o ( f o … )`: a binding given a part of its own value keeps it | §7.6 (#475) | `own_parts` |
| `= o ( f o other )`, the call handed the binding itself and another argument it may hand back: an option or a result owner is refused (no run-time key says which came back), a handle is told apart by its buffer | §7.6 (#412, #419) | `call_lent`, `stmt` (`assign`) |
| A lend handed to a holder that outlives what it borrows is copied where it can be, refused where it cannot | §7.6 | `transfer` |
| A value owned on some paths and lent on others is copied on the paths that lend it, for a holder that outlives the lender | §7.6 | `transfer` (`mixed`) |
| A borrowed value stored into an owner is copied, with the views it holds; one that cannot be copied is refused | §7.6, §2.13 | `rvalue` (`agg`), `apply_call` stores |
| A literal around a part of a parameter is a lend of the caller's value where it is handed back as it is. Taken by anything else, it is copied there, or refused where the part has no copy | §7.6 (#200) | `rvalue` (`agg`), `lit_nocopy`, `lit_lendcopy` |
| A `sink` parameter is the function's own: handed to a new holder, it moves there | §2.1 | `transfer` |
| A place is followed five steps deep (`PATH_MAX`): a walk down a recursive value names the place that deep and stops | - (the engine's bound) | `loan` |
| A `?` / `??` that selects among this frame's owners moves the one it selects into an immutable binding, and out with a return | §2.2 | `stmt` (`let`), `transfer` |
| A literal that is a statement's temporary shows its consumer the bindings it names; they move into it only where it is taken | §7.6 (h693) | `agg_lends` |
| A field read off a temporary leaves it | §7.5 (h323) | `transfer` |
| An owned temporary a callee hands back whole leaves with the result; the result is owned per call | §1 Temporaries, §7.6 | `apply_call` (`whole`) |
| A result owned on some paths and lent on others borrows its argument | §7.6 Call results | `make_summary` |
| …and a binding of it owns it on the calls that made it fresh (an option's `None` is no fresh value): what views it does not outlive the binding | §7.6 Call results | summary `mixed`, `call_mixed` |
| The payload of what a function of the program lent is that call's lend still; the payload of an option a library getter made around an element is the element | §7.6 | `rvalue` (`payload`), `call_by_fn` |
| A cursor given a shorter-lived lend stays a borrow of it; an owner given one is handed a copy | §7.6 | `stmt` (`assign`) |
| A field or a payload of an owned temporary a callee hands back is taken out of it: the result owns it (an element of its buffer is not) | §1 Temporaries, §7.6 (#635) | `apply_call` (`part`) |
| An owned slice moves into the literal that takes it | §7.6 | `transfer` (`stored`) |
| A fresh raw string kept by a value is owned by nothing | §2.13 | `fresh_string_kept` |
| A module global outlives every frame: it holds no view of one | §2.13 | `gstore` |
| A function's exit runs the `;` blocks armed on the way, newest first, after its result is made | §1 | `run_defers` |
| …and before the result leaves the frame: a `;` block still reads the binding handed back, and may not release or change it | §1, §7.2 (#165) | `stmt` (`ret`), `ret_watch` |
| An owned raw string in a binding handed to a keeper is copied; the binding keeps its buffer | §7.6 | `apply_call` (`copied`) |
| A binding a `;` block armed after it may read is released after the chain has run, not where its scope ends | §7.2 | `defer_reads`, `scope_end` |
| A binding of what a call lent out of a temporary is handed a copy | §7.6 | `stmt` (`let`) |
| A `?` / `??` that is owned on some paths and selects an owner on others moves the one it selects, as one that only selects does | §2.2 | `stmt` (`let`) |
| A `~` loop walks its container's buffer: a change to it ends the walk | §2.5 | `foreach`, `walking` |
| A closure holds what it captured: a copy of each handle, the views those hold; one taken by pointer is a `ref` | §2.11, §2.3 | `make_closure` |
| Running a closure reads every capture and does what its body does to them, and to the arguments it is called with | §2.11 | `run_closures`, `closure_arg_effects` |
| A function that runs a closure argument does so at its call; what it hands the closure of its other arguments is in its summary | §2.11 | `invokes`, `cloargs` |
| A closure that changes a capture meets no other argument that reaches it | §2.4, §2.11 | `apply_call` |
| A closure leaves no capture and no argument holding a view | §2.11 | `check_program` |
| A closure kept by an owner, and a literal handed back as it is, copies in what it captured and can copy; a bound closure handed back by name does not | §7.5, §2.11 (h310) | `closure_owned`, `transfer` |
| A closure another thread runs takes the bindings it captured; one taken by pointer may not go. A handle whose copy is a share two threads may use (the type table's `t`) is captured as a share of its own | §2.1, §2.3, §6.5 | `detaches`, `cap_loans`, `thread_share` |
| A closure binding handed to another binding gives it its environment and stays a borrow of it; stored into a literal or handed to a keeper, the holder has a copy | §7.5 (#835, #173) | `closure_moved_into`, `transfer`, `apply_call` |
| A call's lend of a parameter the function keeps on another path is refused where it is handed back (`^ p` itself is the function's to give) | §7.6 (#743) | `calllends`, `check_program` |
| A borrowed closure handed to a keeper is copied: what the callee does to its copy is not done to the caller's | §7.5 | `apply_call` (`copied`) |
| An argument the callee took over and hands back as it is is the caller's own again, holding what it held | §7.5 (#463) | `apply_call` |
| `= b ( wrap b )`: a new value that holds a handle of the binding's old one keeps it; nothing is released | §7.6 (#475) | `stmt` (`assign`, `inside`) |
| A view a closure hands back may point into its arguments, never into what it captured; judged where the closure is made (a captured literal is no view of anything) | §7.5 | `make_closure` (`vback`) |
| Inside a closure, running a closure it was handed may grow or clear what this one captured: the caller's closure may have captured the same | §2.11 | `call_closure` |
| What another thread runs holds no view | §6.5 | `apply_call` (`detaches`) |
| A view handed back out of where it was kept (an element that is a slice or a raw string) points where the kept one points | §2.10 | `apply_call` |
| A closure's result is its caller's own: what it lends out of a capture is copied, and a value that cannot be copied is refused | §7.5 | `check_program` |
| A closure several threads may run changes nothing it captured | §6.5 | `shares` |
| What an `Arc` shares is not changed in place | §6.5 | `effect` |
| A shared payload (`Rc`, `Arc`, `Shared`) is one place per handle type: an effect inside one ends what was lent out of any | proposal D3 | `shared_tails`, `region_effect` |
| A `dyn` method's call may run any impl of the method | §1 Methods | `summary` (`virt`) |
| The drop of a value whose destructor may read its views is a use of them | §2.14 | `scope_end` |
| A copy hook (`S_clone`, `S_share`) hands back a value of its own | §7.6 | `check_program` |
| A closure a callee hands back, or leaves in an argument, runs the body it was made with: the summary names the bodies (`rclos`, `sclos`) | §2.11 | `make_summary`, `apply_call` |
| A copy of a view is that view | §2.13 | `apply_call` (`vcopy`) |
| What an argument holds, its copy and whatever was given its elements hold too, through any number of callees | §2.10, §2.13 | `held` loans, `make_summary` |

## Not rules of the engine

A refusal the fused walk makes on types alone stays the walk's: the raw
memory boundary (docs/spec.md §3.3d), what may cross to another thread
(`Send` / `Sync`, MEMORY.md §6.5), typing. `run.py` counts a probe nurlc
stops that way as decided by the walk (`WALK_RULES`).

The walk's ownership refusals go through one door (`own_die`,
`bck_emit_error`, `g_walk_owns` in compiler/nurlc.nu) that `--emit-core`
passes, so the program reaches the checker whole.

## One IR shape, two answers in nurlc

The probes below have the IR of a refused probe and are accepted by nurlc
today, or the reverse: the walk's answer depends on a spelling the IR does
not have. The engine gives one answer. Which one is PROPOSAL_CORE_IR D4
(the owner's and claude-formal's): the checker takes the answer formal/A2
gives and lists the other side here.

| shape | refused when | accepted when | the checker |
|---|---|---|---|
| `= o ( pick o other k )`, `o` an option owner, `pick` may hand back either argument | `pick` is a plain function defined above the call (`option_owner_given_a_call_that_may_lend_itself_or_another_argument`, agora #412) | `pick` is defined below the call, is a generic instance, or is a `dyn` method (`option_owner_given_back_by_a_callee_below_runs_clean`, `…_by_a_generic_runs_clean`, `…_by_a_dyn_method_runs_clean`): the per-call key decides at run time | refuses all (A2 refuses the form) |

## Declared summaries

A library function whose body uses raw memory has no body the checker can
read: `prims.py` declares its summary (proposal D2). A probe that calls one
with none is skipped and named (`no summary for …`), never guessed.

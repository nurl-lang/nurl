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
| `stale` | what a by-pointer capture's part held when the closure runs (read before the body gave it a value) | nothing; it only marks the read |
| `heldin` | what the captures of a closure parameter hold (what it hands back when it runs: an iterator's elements) | nothing in this frame; each call puts what its closure argument's captures hold in its place |

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
| A binding given a value that views a shorter-lived one is refused where it is used after that one ended, or where it leaves the function holding it, not where it is stored. Stored at once: a pointer into the frame (§2.7), and a view given to a value whose destructor may read it (§2.14) | §2.10, §2.7, §2.14 | `transfer`, `read` |
| Storage the caller holds (an `inout` parameter) may not view this frame's values while a function of the program runs, which may unwind: unless the call is handed that storage and its body's first statement gives it a value that views nothing | §3.3d (#386) | `apply_call`, summary `credits` |
| A closure that reads, through a capture taken by pointer, a part its body did not give a value first reads what the binding holds when it runs: refused where the closure is made or run while that part holds an ended view | §2.3, §2.11 | `stale`, `stale_capture_check` |
| What was bound after a `;` block was armed is released before the block runs | §7.2 | `run_defers`, `defer_before` |
| An owner handed on by name moves; `: ~` of a name is a cursor | §2.2, §7.6 | `transfer`, `move_out` |
| A value that holds a view is read whole only while what the view points into is there | §2.10 | `read` |
| A call's arguments are frozen for its duration: its effects end no view another argument holds | §2.4 | `apply_call` |
| An `inout` argument is the callee's alone for the call: no other argument is the same binding, a part of it or a lend of it. So is one the callee changes without saying `inout`, unless the change is inside a shared handle's payload: that is a change to the one object every share reaches (the `regions` row) | §2.4, §7.7 | `apply_call` |
| A struct literal, or a variant's payload, that names an `in` parameter whole and is handed back as it is keeps the caller's argument: it moves into the result as into a `sink`. Bound, pushed or assigned first, the literal holds a copy; the payload of an option or a result literal is a lend of the caller's value | §1 (temporaries), §7.6 (h207) | `rvalue` (`agg`: `lit_params`), `ret` |
| The payload of an `in` parameter's option or result, handed back as the value of the `??` over it, takes the caller's argument: the result is the caller's own on that path. Handed back by name inside the arm, or out of an enum of the program's, it is lent | §7.6 (h408–h415) | `ret` |
| A function that hands a parameter to a callee that detaches it detaches its argument | §2.7 | `s_detaches` |
| A call's effects come before its stores; a consumed argument is moved | §2.1 | `apply_call` |
| A view-typed parameter (`s`, a slice) is a view the caller lent, never an owner | §1 | `read` |
| An `inout` argument whose binding does not own its value (a `: ~` copy of another binding or of a parameter, a field read, what a call lends; on any path) may not go to a callee that gives the parameter, or a field of it, a new value: the callee releases the old one, which its owner still holds. A `: ~` copy of a local or a `sink` parameter that owns a struct or an enum outright is the exception: after the call it is the value's owner, and the binding it copied is moved | §2.4 (#135, h367–h370) | `apply_call`: `takes`, the borrowed-argument check |
| A `: ~` cursor given, by `=`, a local that owns its value outright takes the value over: the local is moved, and the cursor's slot owns from there on (nurlc's owner-slot flag says at run time whether the slot owns). A cursor given anything else - a part, a parameter, a lend - stays a borrow of what it is pointed at now | §2.2, §7.6 | `stmt` (`assign`: `cursor_lends`), `transfer` |
| A second name of a parameter (`: c p`) handed to a `sink` that keeps the value - in its result, in another argument - takes the parameter's value over through the name, as a keeper does: the function consumes its parameter. A `sink` that releases it may not: the caller still holds the value | §7.6 | `apply_call` (the borrowed-argument check) |
| What is done inside a borrowed value is done inside the place that is the value: of the places a call's lend names (a view of `x.g[*].data` names `x.g` and `x.g[*]` around it too), those whose type is the value's, or, for a view, whose element type is the view's. Where none is, inside every one | §2.4, §2.10 | `effect`: `value_aliases` |
| A closure that leaves an argument or a capture holding what another holds is refused only where the place stored into has room for a view (`view_capable` of its type): a `Value` with String and scalar payloads holds none | §2.11 | `check_program`: the closure store rule |
| A literal handed back as it is (or nested in one) that names a field of a struct the function owns, of a type with no copy whose zero value is empty (nurlc's `z` type flag: a struct of Strings, Vecs, options - not one holding a `% Drop` value directly), moves the field out whole: the struct is left with the field gone, and releases the rest of itself. A field whose zero value would run a `% Drop` is lent, and refused out of a returned literal | §7.6 (h264, h327, AGORA-865) | `rvalue` (`agg`: `ret_aggs`) |
| A call's lend of kind `handle` of a place that holds a number lends nothing: the storage of a `Vec f`'s elements is lent by the `view` beside it | §2.10 | `call` (the lends loop: `scalar_place`) |
| The payload of an option a call made around a lend of a place whose type is the payload's is that place (`json_get` lends `?Json` around a `Json`), not a payload inside it | §7.6 | `rvalue` (`payload`) |
| The payload of an option or a result a local owns, named in a literal handed back as it is, goes over with its option, which is not read after - a value with no copy too | §7.6 (h264's move for a payload) | `rvalue` (`agg`) |
| A function that hands back a view (`s`, a slice) starts its summary at "none": a string literal handed back is static, owned by nobody; a return that hands back an owned one raises it | §7.6 | `initial_summary` |
| A callee "gives an `inout` argument a new value" (the borrowed-argument refusal, the takeover) only where the new value releases the old one: a place that may hold a handle, not a number, not an element of a buffer every copy of the handle sees. A number given a new value ends no handle loan of the value around it | §2.4 (#135) | `releases_in`, `kills_paths` |
| A payload whose type owns nothing and has no room for a view (an error code and an offset) borrows nothing, whatever its option lends | §7.6 | `rvalue` (`payload`) |
| A `?` / `??` or a value block that "selects among owners" selects only places of the binding's type (or an option or a result around one): a reader over a Vec's bytes selects no Vec | §2.2 | `stmt` (`let`): `is_value_place` |
| What a `;` block armed in a loop body may read - the names it reads, and what their values hold or borrow (a closure's captures) - is kept until the chain runs | §7.2 (agora #655) | `defer_reads` |
| A number written into a buffer's element is no change another argument must not reach: every holder of the buffer sees it, and nothing it views ends | §2.4 | `apply_call` (`changed`) |
| The text of a String a local owns - a field of a local struct too, whatever the local borrows on other paths - handed back as a call lent it (`^ ( string_data . a s )`) is copied for the caller. Not the text of a loop's element, nor of an arm's payload | §7.6 (agora #471, #679) | `transfer`: `text_of_local` |
| Where in a value a loan is held is followed HELD_MAX (8) steps deep; held deeper, it is held at the prefix. A loop that stores into a value what the value already holds re-roots it under itself every round: without the bound the paths grew without end (embed's weight loader: 10 M paths, killed) | §2.10 | `hroot`, `held_root` |
| A payload taken out of a call's temporary - and a binding a literal shows, when the literal is taken - carries what it holds of its own parts with it: those loans name its new holder (a tokenizer's piece table viewing its own buffer, moved into the engine it builds) | §7.6 (selfholds) | `rebase_self`, `move_out` |
| One loan is held in at most HELD_WIDEN (8) places of a value; held in more, it is held at their longest common prefix (a widening: sound, as a loan held at a prefix is held at every place below it). Without it the places multiplied combinatorially (nurllama's loader: 6 M, > 5 min; with it 2.2 s) | §2.10 | `widen_held` (`AV`), `held_widen` (`av_make`) |
| A part of an `inout` parameter handed to a callee that keeps it (in its result, in another argument) is copied where its type has a copy: the caller goes on holding the whole. A callee that releases it takes it | §7.6, §2.4 | `apply_call` |
| A value that owns nothing (numbers, and a struct of numbers and views: nurlc's "no drop") given a new value, dropped or taken releases nothing: no handle or view lent through it ends (`= r next` over a reader of a model's bytes) | §2.10 | `kills_paths`: `owns_nothing` |
| The `inout` exclusivity holds only for arguments the callee changes in a way that may end what another argument views: a new value that releases (not a number, not an element written in place), a reallocation, a drop, a part moved out. An `inout` the callee only reads needs none (`__tpl_seg_eq inout r … nm`, `nm` read out of `r`) | §2.4 | `apply_call` (`changed`) |
| An arm's payload of an option or a result a local owns, with no copy, stored into a field (`= . m tok t`) goes over with its option | §7.6 | `stmt` (`assign`): `own_payload` |
| `*` of an enum of the program's whose container payloads all hold one element type (`Json`: `JArr ( Vec Json )`, `JObj ( Vec Json )`) is that type: what a walk down the value reaches | §7.6 | `Types.elem`, `et_elem` |
| An arm's payload whose copy would go on viewing itself where it sits in its option is taken with its option, not copied (its self-views follow it: `held_of_own`) | §7.6 | `stmt` (`assign`) |
| A lend of a binding declared after a holder whose drop may read what it holds (released before it, newest first) is copied into the holder's field where it has a copy, as a lend of an inner scope's binding is | §2.14 | `stmt` (`assign`) |
| A closure that gives a field of its `inout` argument a capture whole gives it a copy, where the field's type has one, as one that gives the whole argument | §2.11 | `check_program`: the closure store rule |
| A part of an element of any parameter's container, handed to a callee that keeps it, is copied where it has a copy (`_ar_job . cx sp . cx w …`, `cx` an element of an `in` Vec) | §7.6 | `apply_call` |
| What a `;` block binds lives on after the block until the whole chain has run (a block armed inside a block, which runs after it, reads it; an older block reads a holder the newer one pointed at its own value): released then, newest first | §7.2 | `run_defers` (`chain_scopes`, `chain_kept`), `scope_end` |
| A literal around a part of a parameter that a callee keeps by value is copied there, and the bindings it names move into the copy (`( vec_set … @ W { n q h . m aux } )`) | §7.6 | `apply_call` (stores) |
| Of the places a call's lend names, one its path cannot reach - a variant's payload asked of a Vec or a struct, a field of a Vec, an option, a number - is dropped where a reachable one is left (`json_obj_get` lends `#JObj0` and `#JObj0[*]`; `json_arr_get` of that is `#JObj0[*]#JArr0`, not `#JObj0#JArr0`) | §2.10 | `call` (lends): `ill_typed` |
| A closure's own parameter assigned whole over a capture taken by pointer (`= best r`) is copied in, and the capture owns the copy; a parameter with no copy is refused (nurlc, agora #864) | §2.11 | `stmt` (`assign`) |
| A function whose summary is the walk's (it crosses the raw boundary) and changes a parameter only through a handle that synchronises itself - the walk's thread rules say so (`syncd` on its `sum` line, `__thr_unsync_change`) - makes no change to that parameter's value, which an Arc may freeze: its change is inside the payloads of the shared handles the parameter reaches (`regions`), an Arc's excepted (`mcp_server_envelope_as` over `arc_get` of a server: its task store is a `Shared` behind its own mutex) | §6.5 | `derive.py`, `eng_derive` |
| What a closure's body leaves an argument or a capture holding of a capture taken by value is judged where the closure is made, by what the captured value holds then: refused if it holds a view or a lend (not a share), accepted if it holds none (a fresh buffer). A capture taken by pointer, whose value may change after, is refused by the summary rule as before | §2.11 | `make_closure`, `check_program` |
| What is done inside a part of a value that is a view (a slice field over another binding's buffer, `= . x w ( slice_from_vec … )` then `( slice_put . x w 0 … )`) is done to what the view points into, as for a binding that is a view: an Arc's payload written through such a field is refused | §2.10, §6.5 | `effect` (held views) |
| A call through a closure value freezes its arguments as any call does: the body may not end, through what it captured, what an argument borrows (`( c e )`, `e` a payload of the option `o` the body replaces) | §2.4 (agora #445) | `call_closure` |
| A `: ~ s` slot given what a call hands back as its caller's own on some calls owns it there (nurlc's owner-slot flag), and the keep rule over such a call (`= rest ( next_of rest 1 )`) ends what was lent out of the old value - on the calls that answer with a fresh one, the old one goes | §7.6 ("Call results") | `stmt` (`assign`) |
| A closure stored into what two threads may share - a channel, the payload of a thread-shared handle - may be run by the other one: it takes its captures with it, as one a thread is spawned on does (h340) | §6.5 | `apply_call` (`dets`) |
| A closure a function was handed, handed on to a closure that runs it, is run by the function, on what that closure hands it: the function's `invokes` and `cloargs` say so (agora #420) | §2.11 | `call_closure` |
| The argument a callee changes is its place and what it is a cursor or a lend of: another argument reaching any of them breaks the exclusivity (`( walk t cur )`, cur a `: ~` cursor of t; agora #589) | §2.4 | `apply_call` |
| A `: ~ s` binding born owning (from a literal, from a fresh value) takes its own copy of any value that is not fresh: it holds no view of where the value came from | §7.6 (owned string slots) | `own_slots`, `transfer` |
| A closure whose body gives a binding it captured by pointer a new value, where that binding borrows its value (a `: ~` copy of another): the binding owns the new value, and what it borrowed stays its owner's, untouched | §2.11 | `run_closures` |
| A capture with no copy, stored into a literal by the closure's body, moves out of the closure: it may run once (run again, it panics) | §7.5 (h222, h224) | `transfer`: the capture branch |
| A closure binding reached through a pointer (an `inout` parameter, a capture taken by pointer) is a place that owns its closure, as a field is: a closure stored there copies in every capture that has a copy | §7.4 (h297) | `stmt` (`assign`), `closure_owned` |
| A share of a shared handle borrows no binding: a value that holds one may outlive the binding the share was copied from | §6.5, §7.5 | `local_depth` |
| What a closure's body changes inside a shared payload is changed where the closure is run, in every payload of that handle type (`regions`) | §2.2 (#845) | `run_closures`, `region_effect` |
| A literal handed back as it is keeps an `in` parameter it names whole also where the parameter has no copy: until the return takes it the literal is a lend of the caller's value, and anything else that takes it is refused. The same through an option or a result literal around it. The result owns what it took | §7.6 (h207, #796) | `rvalue` (`agg`): `lit_params`, `lit_nocopy`; `ret` |
| A closure's capture that has a copy, handed to a function that keeps its `in` parameter, is handed over as a copy: the closure keeps its own. A `sink` takes the capture itself | §7.5 (#796) | `apply_call`: consumed arguments |
| A lend stored into a field whose holder outlives what the lend borrows is copied in, where the field's type has a copy; with none it is refused | §7.6 ("borrowed values are copied into owners") | `stmt` (`assign` to a part), `transfer` |
| A temporary made in an arm of a `?` join that the arm's value may view is the enclosing statement's: no scope ends it, its `drop` does (the IR's `v` flag 16) | §1 (temporaries, #138) | `scope_end`, `stmt` (`drop`) |
| An `inout` argument of a closure given a capture or another argument whole is given a copy of it, where its type has one: no store the closure's type would have to tell. A capture taken by pointer is given the handle itself, which is refused (agora #864) | §2.11, §2.12 | the closure-exit check (`real`) |
| A borrow handed to a consumer: a part read in place is taken out of its owner; a call's lend in a temporary is copied; a binding of a call's lend is refused | §2.5, §7.6 | `apply_call`, `take_payload` |
| A field taken out of its owner is not read, nor the value handed on whole, until it is given a value again | §2.1 | `State.gone` |
| A part taken out of an `inout` parameter is a change to the caller's binding, not a hand-over of it; left taken at an exit, it is gone in the caller's binding | §2.1, §2.12 | `take_payload`, summary `gone` |
| An `inout` parameter handed to a consumer: the consumer is given a copy, the binding keeps its value, and what the caller lent out of the binding ends (the call may have given it a new value) | §2.12 (#776) | `apply_call` (`copied`) |
| A lend of an element given back to the same element is read before the old value goes | §2.4 | `apply_call` (`stored_back`) |
| A store replacing a place hands its old value to the binding that read that very place: the first one; a later reader of the same place borrows from it | §7.6 (#265) | `handover` |
| A `: ~` cursor of a binding kept by value (pushed, stored into a literal) hands the binding on: the binding is moved through it, and the cursor reads the value where it went | §7.6 | `apply_call` stores, `rvalue` (`agg`) |
| What was lent out of a temporary follows it into the binding it moves to | §1 Temporaries | `rehome` |
| `= o ( f o … )`: a binding given a part of its own value keeps it | §7.6 (#475) | `own_parts` |
| `= o ( f o other )`, the call handed the binding itself and another argument it may hand back: an option or a result owner is refused (no run-time key says which came back), a handle is told apart by its buffer | §7.6 (#412, #419) | `call_lent`, `stmt` (`assign`) |
| A lend handed to a holder that outlives what it borrows is copied where it can be, refused where it cannot | §7.6 | `transfer` |
| A value owned on some paths and lent on others is copied on the paths that lend it, for a holder that outlives the lender | §7.6 | `transfer` (`mixed`) |
| A borrowed value stored into an owner is copied, with the views it holds; one that cannot be copied is refused | §7.6, §2.13 | `rvalue` (`agg`), `apply_call` stores |
| A literal around a part of a parameter is a lend of the caller's value where it is handed back as it is. Taken by anything else, it is copied there, or refused where the part has no copy | §7.6 (#200) | `rvalue` (`agg`), `lit_nocopy`, `lit_lendcopy` |
| A `sink` parameter is the function's own: handed to a new holder, it moves there | §2.1 | `transfer` |
| `dyn Trait x`, x a value the caller keeps (a parameter, a field read): the box is given a copy, where one can be made | §1 Methods | `apply_call` (`copied`) |
| A raw string a closure hands back is copied: the caller's own, whatever buffer the body read it out of | §7.5 | `make_closure` |
| The text of a local String, as a call handed it back (`^ ( string_data x )`, `^ ( view_of x )`), is copied at the return; a binding of that view handed back is a view of a released local | §7.6 (#663) | `transfer` |
| A place is followed five steps deep (`PATH_MAX`): a walk down a recursive value names the place that deep and stops | - (the engine's bound) | `loan` |
| A `?` / `??` that selects among this frame's owners moves the one it selects into an immutable binding, and out with a return | §2.2 | `stmt` (`let`), `transfer` |
| A literal that is a statement's temporary shows its consumer the bindings it names; they move into it only where it is taken | §7.6 (h693) | `agg_lends` |
| A field read off a temporary leaves it | §7.5 (h323) | `transfer` |
| An owned temporary a callee hands back whole leaves with the result; the result is owned per call | §1 Temporaries, §7.6 | `apply_call` (`whole`) |
| A result owned on some paths and lent on others borrows its argument | §7.6 Call results | `make_summary` |
| …and a binding of it owns it on the calls that made it fresh (an option's `None` is no fresh value): what views it does not outlive the binding | §7.6 Call results | summary `mixed`, `call_mixed` |
| What a function hands over counts every value the returned binding was given: fresh on one path and a lend on another, filled through an `inout` callee. A payload matched straight out of such a call is in the call's own storage on the fresh calls, released with the `??` | §7.6 Call results (agora #679) | `ret` (`ret_fresh`), `apply_call` (`var_fresh`), `match` |
| The payload of what a function of the program lent is that call's lend still; the payload of an option a library getter made around an element is the element | §7.6 | `rvalue` (`payload`), `call_by_fn` |
| A cursor given a shorter-lived lend stays a borrow of it; an owner given one is handed a copy | §7.6 | `stmt` (`assign`) |
| A field or a payload of an owned temporary a callee hands back is taken out of it: the result owns it (an element of its buffer is not) | §1 Temporaries, §7.6 (#635) | `apply_call` (`part`) |
| An owned slice moves its buffer to whatever is given it — a new binding, an assignment, a field, a literal — as any owner does; an owned raw string in a binding is viewed or copied instead (§2.13) | §2.1, §2.2, §7.6 | `transfer` |
| A field or a payload of an `in` parameter kept by value (pushed, stored) is taken out of it: the function owns the parameter from there and the caller's argument moves into the call. So is the payload of a local option or enum, through the `??` binding over it | §7.6 (h389–h404, h421–h423), §2.11 (agora #170) | `apply_call` stores |
| An option's or a result's payload taken through its `??` binding leaves the option unreadable until it is given a value again. A field taken through a binding of it is left an empty String or Vec, and the payload slot of an enum of the program's is left empty the same way | §2.1, §2.11 (agora #170, #175) | `take_payload` |
| A value that cannot be copied has no empty state to leave behind: a field of that type is not taken out of its struct, nor a payload of that type out of an enum of the program's: the read is a lend, and what would own it is refused. An `inout` parameter given such a lend is refused too | §7.6 ("Values that cannot be copied", h322–h327, agora #641), §2.12 (agora #697) | `take_payload`, `assign` |
| What a `?` / `??` selects among this frame's owners moves out with a return; not from under an armed `;` block, and not out of a value block whose local it is: there the arm is a lend, copied, and refused for a value with no copy. A binding over a join whose arm is the payload of an option a field keeps, with no copy, is refused the same way | §2.2, §7.6 (agora #186, #188, h227) | `transfer`, `let` |
| A fresh raw string kept by a value is owned by nothing | §2.13 | `fresh_string_kept` |
| …stored into a field too (`= . r name ( nurl_str_cat … )`); and a raw string a parameter holds, kept by value, is kept as a view of it - a `sink` parameter's is released on the way out, so a function that keeps, in what its caller holds, a view of a `sink` parameter it releases is refused | §2.13 | `stmt_assign`, `apply_call`, whole function |
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
| A closure that changes a capture meets no other argument that reaches it. One the callee runs — handed as it is, or inside an option, a struct or a container — that changes the payload of a shared handle meets no argument that may be another handle on that payload: the callee's view through it would end under it | §2.4, §2.11, §2.2 (agora #736) | `apply_call` |
| A closure leaves no capture holding a view, and no `inout` argument. What it leaves one by-value argument holding of another is followed where the call that runs it is seen | §2.11 (#403) | `check_program`, `closure_arg_effects` |
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
| A join whose arm is an owned raw string of a binding that lives on hands the join a copy of its text | §7.6 (owned string slots) | `transfer` |
| A mutable raw-string binding born owning takes a copy of the text it is given, and any such binding one of an owned raw string of another binding. One born from a view is a cursor: given a cursor that owns its value on some paths only, it is pointed at it, and reads it no longer than that cursor lives | §7.6 (owned string slots, h119) | `transfer` (`cursor_slots`) |
| A function that hands back what a call lends out of a parameter it takes over on another path is refused, a join with a fresh arm included | §7.6 (agora #743) | `check_program` (`calllends`) |
| A slice literal owns its elements: one that names a binding or a parameter is given a copy of it | §7.6 (agora #485) | `rvalue` (`agg`) |
| A value block whose tail names a binding of an outer scope, or a field of one, only lends it: a consumer is given a copy | §2.12 (agora #555) | `apply_call` (`block_temps`) |
| An element taken out of a container parameter (a loop's element handed to a `sink`) is a change to the container's elements, not a take-over of the container. A loop's element with no copy is not taken; nor is a field of a binding of what a call lent; nor a payload of what a shared handle lends | §2.5, §2.10, §7.5 (agora #588, #669, #680, #463) | `take_payload`, `apply_call` |
| A `;` block armed in a round of a `~ x xs` loop runs at the function's exit, outside every round: there the element is a view of the container's element, and a field of it handed to a `sink` is refused, as a `vec_at` copy's is (`fe_walking` → `defer_fe` → `fe_outside`) | §2.10, §7.2 (agora #672) | `run_defers`, `apply_call` |
| An arm's payload of an option a local owns, handed out by a value `??` (`: String t ?? o { T s → s … }`), goes over with its option, as nurlc moves it: the option is moved on that path (agora #175) | §7.6 | `stmt_assign` |
| The payload of what a library getter lent (`vec_get`, `lru_get`) handed to a `sink` that releases it (keeps it nowhere) is refused: the container still holds it - only a `~` loop's element is taken out of its slot; a callee that keeps it is handed a copy (h299) | §2.10, §7.6 | `apply_call` |
| A field of a closure's by-value capture handed to a `sink` is refused: the body works on its own copy, and the binding outside releases the field again (nurlc's `pendfc`) | §2.11, §7.5 | `apply_call` |
| A field of a copy of a value the frame only borrows - a by-value (`in`) parameter (not a destructor's receiver), a `~` loop's element, a closure's by-value capture or parameter - given a value that owns memory is refused: the store lands where the owner never looks, and nothing releases it (agora #488, #643) | §5.4, §7.2 | `stmt_assign` (`borrowed_copy`) |
| A field of a binding stored into a field (`= . b c . p c`) is a borrow the holder would own: copied where its type has a copy, refused where it has none | §7.6 | `stmt_assign` |
| A closure call whose known body hands back a slice (`slice_from_vec w`) lends what the body's `lends` name: of the arguments, and of what its captures point at; a value of any other type - a raw string too (h220) - is copied (§7.5) | §2.11, §7.5 | `call_closure` |
| …and a result that holds what a capture holds (`rholds` of a capture: the views a captured Vec's elements are) holds them where the closure value holds them; a known body with no summary (a library's closure) hands back, as an unknown one does, what the closure's captures hold | §2.2, §7.5 (agora #472) | `call_closure` |
| A derived summary (the walk's answers): a closure parameter the function only runs is kept nowhere, but its result, where its type has room for a view, holds what that closure's captures hold (`heldin`: `iter_find` hands back what its iterator produced) | §2.2 (agora #472) | `derive` |
| A function that hands back an element of an `in` parameter it takes over on another path (a loop's element, a `vec_get` payload) is refused, copyable or not: the parameter is released on that path, and an element is not copied back as a field is (agora #765, #677) | §7.6 | whole function |
| The payload of an option a callee made around a lend of an element (`vec_get`) holds what that element holds - the lend put it at the option's own root (a closure read out of a Vec of closures) | §2.2, §7.5 (agora #736) | rvalue `payload` |
| A parameter, or a part of one, handed to a callee that runs what it holds is run by this function (`invokes`), as a closure parameter called directly is | §2.11 (agora #736) | `apply_call` |
| A call's other arguments are frozen against the closures it runs: one that reaches a shared payload such a closure changes (its `regions`, or a change under `*` of a capture that is a shared handle) is refused | §2.2, §2.4 (agora #736) | `apply_call` |
| A closure run whose body changes, through one capture, what another of its captures views (a Vec grown, a slice of it read) is refused: the body reads that one too, in this run or the next | §2.11 | `run_closures` |
| `signal_install` keeps its handler past the call (declared: `detaches` the closure, as `thread_spawn`) | §2.11 | prims |
| A raw string captured by value is a copy of its address: the closure holds a view of the binding's buffer, which stays the binding's (no move) - a closure another thread runs, or one handed back, may not hold it | §2.13, §6.5 | `make_closure` |
| What another thread runs holds no copy of the views a parameter holds (a clone of a `( Vec s )` parameter), unless the same capture holds the parameter itself (its views go with their owner's value); and a binding read out of a library handle field, captured by it, takes the handle over: its owner is moved | §6.5 | `apply_call` (detaches) |
| A swap or a reverse moves elements between slots and releases none: a handle of an element and a view of its buffer stay good; a loop walking the container is upset (effect `permute`) | §2.5 | `effect`, `prims.py` |
| A parameter of a type with nothing to release (a struct of views and numbers: nurlc's `drops` answer) is copied by its words: its new holder holds the views it holds and nothing of the parameter | §2.13 | `transfer` |
| What goes into a shared handle's payload is held by the one object every share reaches: a binding that may be another handle on it holds it too | §2.10 (agora #392) | `store_into` |
| A view of a binding's buffer kept elsewhere follows the binding into the container, the literal or the field that takes it | §2.10 (agora #337) | `rehome_views` |
| A summary's effect says what may happen. A parameter the callee gives a new value on every path goes back holding none of what it held; one that goes back, on some way out, still holding it (`keeps`) keeps what it holds at the call: what was lent out of it ends all the same | §2.10 (AGORA-863) | `make_summary`, `apply_call`, `effect` (`weak`) |
| A loop whose condition is a true literal ends only at a `break` or a return: what holds after it is what held there | §2.5 | `loop` (`loopcond T`) |
| The result of a call through a known closure holds of its arguments what the body's summary says its result holds of its parameters | §2.8 (agora #422) | `call_closure` |
| What a closure the caller chose hands back may hold what its captures hold (not its handles of the captures themselves): a function that collects such results hands them on | §2.11, §2.10 | `call_closure`, `heldin` |
| A closure's result is its caller's own: what it lends out of a capture is copied, and a value that cannot be copied is refused | §7.5 | `check_program` |
| A closure several threads may run changes nothing it captured | §6.5 | `shares` |
| What an `Arc` shares is not changed in place | §6.5 | `effect` |
| A shared payload (`Rc`, `Arc`, `Shared`) is one place per handle type: an effect inside one ends what was lent out of any | proposal D3 | `shared_tails`, `region_effect` |
| A `dyn` method's call may run any impl of the method | §1 Methods | `summary` (`virt`) |
| The drop of a value whose destructor may read its views is a use of them | §2.14 | `scope_end` |
| A binding whose release runs such a destructor (its own, or one in a field, an option's or result's payload, an element, a library handle's type argument) gains no view of a binding declared after it: refused where it gains it, by an assignment or through a call that stores into it, because the younger one is released first on every way out | §2.14 | `younger_views` |
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

| `^ ( id x )`, `x` an owned raw string of this frame, `id` handing its argument back | `id` is defined below the function (`identity_of_a_fresh_s_binding_returned_callee_below`) | `id` is defined above it (`…_callee_above_runs_clean`): the text is copied at the return | accepts both (the copy) |
| `? c x l` as a function's value, `l` a local with no copy, `x` a parameter or a fresh value | it is the body's fall-off value (`drop_param_local_fall_off`, agora #186: "would have to be copied") | it is written `^ ? c x l`: the selected local moves out | accepts both (the move) |

### One operation, three answers by spelling

Not the same IR, but the same thing done: a function hands back a value
that is, or is built around, an `in` parameter or a part of one. nurlc's
answer (its `sum` line) follows how it is written. The checker copies
each, so that the probes agree; an engine that decides the drops itself
(stage S3) can give one answer for all of them, and which is D4 too.

| written | nurlc's answer | the caller's argument |
|---|---|---|
| `^ p`, `^ . p f`, `?? p { V x → { ^ x } }`, `^ ?? e { V x → x … }` over an enum of the program's, `^ @ ?T { T p }` | lent (`retpart`, `ret_borrow`, per call where another path is fresh) | stays the caller's; the result borrows it |
| `^ ?? o { T x → x F → … }`, `o` an option or a result | taken (`sink`, `keeps`): h408–h415 | moved into the call |
| `^ @ K { p }`, `^ @ E { V p }`, `^ @ ?K { T @ K { p } }` | kept (`keeps`, `stores`): h207 | moved into the call |
| `^ @ KK { @ K { p } }` | lent (`ret_borrow`) | stays the caller's |
| `: K k @ K { p }` then `^ k`; `( vec_push out @ K { p } )`; `= . o f @ K { p }` | a copy of `p` is made | stays the caller's |

## Declared summaries

A library function whose body uses raw memory has no body the checker can
read: `prims.py` declares its summary (proposal D2). A probe that calls one
with none is skipped and named (`no summary for …`), never guessed.

# Proposal: one ownership engine over a core IR

Status: **under way** (Agora AGORA-441, proposed 2026-11-13): S1 is in the
compiler (AGORA-858), S2's engine runs in shadow beside the walk
(AGORA-859, AGORA-863). The document came with a working prototype of the
checker it proposes (`tools/ncore/`) and the measurements below.

**Where it stands.** S1 is in the compiler (AGORA-858): the walk builds
the core IR and `nurlc --emit-core` prints it. [CORE_IR.md](CORE_IR.md)
describes it, and `tools/ncore --nurlc` runs the reference checker on what
nurlc lowers instead of on its own parser's lowering.

S2 is in shadow (AGORA-859, AGORA-863). A program the walk refuses on an
ownership rule reaches the IR whole (one door, CORE_IR.md §6), the IR
carries the walk's own summaries of the functions whose bodies cross the
raw boundary (`sum` lines), and the reference checker's rules are a table,
[tools/ncore/RULES.md](../../tools/ncore/RULES.md), each row with the
section of docs/MEMORY.md that states it. That table is what the engine in
nurlc transcribes. The measure of the table is two-sided: the hole probes'
`// map:` verdicts (does it refuse what nurlc refuses), and the programs
nurlc accepts (`run.py --clean` over examples/ and compiler/tests: does it
refuse nothing nurlc accepts). The numbers are in the AGORA-859 thread.

**The engine is in the compiler, in shadow** (AGORA-863): the table
transcribed into `compiler/nurlc.nu`, run by `nurlc --engine` on the IR of
the module being compiled; a compile is still the walk's. Measured against
the reference checker (`tools/ncore/engcmp.py`):

| | the engine gives the reference's verdict on |
|---|---|
| hole probes | 3,495 of 3,495 |
| `compiler/tests` with a `COMPILE OK` golden | 1,117 of 1,118 (the other: the reference does not finish in its time limit; the engine answers in 0.08 s) |
| `examples/` | 65 of 65 |
| `compiler/nurlc.nu` itself | both accept it whole (3,315 functions, the engine's own among them) |

Its cost on the compiler's own source is 4.0 G instructions; the borrow
walk it is to replace is about 6.9 G of the 24.6 G self-compile (§10,
line 2). The reference takes about ten minutes on the same input.
Writing it found two things the reference had wrong, both fixed in the
table and in the engine and pinned by probes: a callee's "gives its
parameter a new value" was taken for certain when it holds on some paths
only, and a closure run under `recover` was taken to run to its end.
[CORE_IR.md](CORE_IR.md) §7 says where the engine is and how it runs.

What the table has shown so far for §7:

- **D2** has a bridge and a measured scope. Until summaries are declared
  in source, the walk's own answers for a raw function are read out of its
  tables (`sum` lines, `tools/ncore/derive.py`). Three runs over the hole
  probes say where a declared summary is needed:

  | summaries used | probes that agree |
  |---|---|
  | hand-declared for about 220 functions (`prims.py`), the walk's tables for the other raw ones | 3,182 |
  | the same, but every library function whose body stays inside the raw boundary is walked, declared or not (`NCORE_WALK=1`) | 3,180 |
  | no hand-declared summary at all (`NCORE_WALK=1 NCORE_DERIVE=1`) | 2,975 |

  A function whose body stays inside the raw boundary needs none: the
  engine reads its body. The raw core (`vec_*`, `string_*`, `rc_*`,
  `arc_*`, `map_*`, the channels) does: what nurlc knows of it today is
  partly by name, and its tables alone lose about 200 probes. That is the
  set D2's declarations have to cover first.
- **D4** has its first concrete list: shapes with one core IR that nurlc
  answers two ways, depending on a spelling the IR does not have
  (RULES.md, "One IR shape, two answers in nurlc"). The engine gives one
  answer for each; which one is the decision.

## 1. The decision asked

Stop closing memory-safety holes one surface shape at a time. Replace the
borrow walk (`bck_*`) and the drop decisions in `mem_*` with **one
ownership engine** that runs over a **core IR**, the statement language of
the formal model (formal/A2), which the front half of the fused walk emits
for every function. Land it in stages (§9), with the old checker in place
until the new one agrees with the probe corpus, while agents stop editing
the ownership parts of the compiler.

## 2. Why: what the last weeks measured

**The patching path does not converge.**

| main | `nurlc.nu` lines | hole probes | open holes (`tools/fuzz/holes/open/`) |
|---|---|---|---|
| 2026-10-15 | 56,991 | 259 | 0 |
| 2026-11-01 | 72,591 | 1,185 | 31 |
| 2026-11-07 | 78,880 | 1,904 | 61 |
| 2026-11-13 | 99,543 | 3,488 | 47 |

In the last six days the compiler grew by about 3,400 lines a day, almost
all of it in fixes for one shape each. Over 3–7 days hole tickets open and
close at the same rate, about 60 a day each way. 26–32 % of all hole
tickets are explicit "#N's rest" children of an earlier fix. 105 of 358
closed ones spawned at least one child, and the longest chains run five
deep (#496 → #656 → #802 → #817 → #838, still open).

**Where the holes come from.** The 44 open holes that accept an unsafe
program, the 25 open precision refusals and the 200 most recently closed
soundness tickets, classified by root mechanism:

| set | n | S surface form | M summary | P path granularity | T threads | L leak / lost write | other |
|---|---|---|---|---|---|---|---|
| open, accepts unsafe | 44 | 17 | 7 | 7 | 4 | 7 | 2 |
| open, refuses safe | 25 | 3 | 4 | **17** | 0 | 0 | 1 |
| closed, newest 200 | 200 | **91** | **46** | 19 | 19 | 11 | 14 |

- **S**: one ownership shape handled in one spelling and missed in another
  (a join, a value block, a try, a defer, a keyword call, a field path vs.
  an alias, a statement vs. an expression).
- **M**: the caller cannot know what a callee keeps, lends, changes or drops
  (closures as values 19 of 46, the same `Rc` 9, `dyn` 2, definition order /
  recursion / generics 3, the rest summary encodings).
- **P**: facts kept per binding or per parameter where a field path or an
  element matters. Every open P ticket is a precision refusal that a
  soundness fix caused ("soundness first" coarsens the per-binding domain).

**Why the compiler produces them** (a map of the machinery at a8aca0ec):

- About half of `nurlc.nu` is ownership machinery: the borrow walk 18.8k
  lines, drop and ownership codegen (`mem_*` and kin) 18.4k, closures /
  effects / holders 8.5k, module-end passes 4.0k. On top of that, 18–40 % of
  the `gen_*` functions' code (`gen_call_body` is 4,517 lines) names
  checker or ownership state.
- **There is no canonical form.** The checker reads a log of rows that 59
  functions write in surface terms, with 807 calls into `bck_*` from 237
  functions and 122 `g_bck_*` globals acting as hidden registers. Field 8
  of a row is a second expression language (52 `__sx_*` functions build
  it, `bck_sx_ev` parses it back). `pend*` rows are written out of
  evaluation order (#604, #680).
- **The state is split.** A per-path byte lattice, 76 per-binding fact
  families outside it (only some journalled at joins), the closure graph,
  the `origin_*` address graph, raw provenance and implication records:
  each has its own join and fixpoint, with a 16-round loop cap and a
  64-round "may" fallback. About 30 module-end passes run in a fixed
  order, and their comments record the order constraints (#461, #770,
  #800).
- **Two ownership engines must agree.** The walk decides what to refuse,
  `mem_*` decides what to drop, and each reads the other's facts. Codegen
  loads 19 families of `@.__nurl_*` flags decided from the walk's answers.
  158 of the 1,568 run-clean probes compile to different IR without
  `--no-borrowck`. A hole is often the two engines disagreeing, so every
  fix is made twice.
- **Cost.** The checker is 28 % of a self-compile (21.0 G instructions and
  3.80 s with it, 15.0 G and 2.69 s without).

**What the formal model already says.** A2 has no surface forms. Its
statement language is `letv`, `letcall` with every argument named,
`assign`, `ite`, `while`, `scope`, `free`, `unpair`. A call is checked
against the callee's **summary**, an `Fn` record with parameter modes,
`resOwn`, `lends`, `rholds` and `outHolds`, and each body is checked against
its own summary (`FnOK`), so recursion needs no special case. Of the open
holes, CLAIM.md places about 29 "inside A2": a checker that transcribed A2
would close them by construction.

## 3. Diagnosis

1. **No canonical form.** Each producer × consumer × context pair is its own
   code path. ELABORATION.md (#222) showed the N×M pattern for joins and
   blocks. It holds for every construct.
2. **The facts live in many places with many fixpoints.** Holes appear at
   the seams.
3. **Two engines.** Refusals and drops are decided apart and must agree.
4. **Bindings, not places.** Dependencies are per binding with a one-level
   element mark, so precision and soundness trade against each other.

None of these is fixed by another shape. They are fixed by the
architecture.

## 4. The design

### 4.1 The core IR

A2's statement language, extended only where nurl has more:

- **Statements:** `let`, `assign` to a place, `eval`, `if`, `match` (a
  payload binding is a statement of its arm), `while`, `foreach`, `scope`,
  `drop`, `ret`, `break`, `continue`.
- **Places:** a variable id plus a path of field names, `*` (an element)
  and `#V i` (payload `i` of variant `V`).
- **Operands:** a place read or a constant.
- **Rvalues:** `use`, `call` (every argument an operand), `agg` (a
  literal), `payload`, `scalar`.

Every producer lands in a temporary before anything consumes it: a call, a
join, a match, a value block, a literal. This is ELABORATION.md's rule
applied to all forms. Names are resolved to ids when the IR is emitted.
Statements are written in evaluation order. The fused walk keeps parsing
and typing and emits the IR per function. It already knows every type,
temporary and evaluation point, so the IR is a by-product of what it
does.

### 4.2 One analysis

A forward dataflow over the IR, with joins at merges and fixpoints at
loops. Per variable it tracks:

- **own:** owner / parameter / lent / moved / maybe-moved / released;
- **loans:** what the value needs to stay valid;
- **alias:** what it is a handle or a view of;
- **held:** loans kept inside it, by path (`.idx[*]` views `.arena[*]`).

A **loan** is a place plus a kind:

- **handle:** a copy of the place's handle;
- **view:** a pointer into its own buffer.

A2's `Eff.kills` decides which loans an **effect** on a place ends. The
effects are `realloc` (its buffer may move), `drop` (its elements may be
dropped) and `replace` (its value is replaced or released). The table is
lifted from bindings to places:

- an effect on an ancestor ends what lies under an element of it;
- an effect inside a struct ends a handle copy of that struct.

**A use of a value whose loan has ended is the error.** There is no other
kind of borrow error. A move, a scope end, a `sink`, a call's effects and a
store are all effects or ownership changes on places. One rule catches
each, whatever the spelling.

### 4.3 Summaries

A summary is A2's `Fn` with paths:

- `modes`, `res` (owned / lent / nothing);
- `lends` (k, path, kind);
- `rholds`;
- `effects` (k, path, eff);
- `stores` (j, dpath, k, path, kind), which is A2's `outHolds`;
- `consumes`, `elems`.

**Program functions** are summarised by the same analysis. It runs over the
whole program until no summary grows. Summaries only grow, so this ends,
and definition order plays no part. Parked walks, retfwd passes and
"callee compiled later" paths all disappear.

**`unsafe`, `raw` and FFI functions declare their summaries.** This is the
trust boundary MEMORY.md §6.4 already names. Today those summaries are
tables inside `nurlc.nu` and attributes on runtime declarations; they move
into the stdlib source next to the function they describe.

### 4.4 Drops come from the same state

Whether a place is owned, moved or maybe-moved at a scope end is exactly
the information a drop and a drop flag need. Codegen asks the engine. It
does not keep a second ownership model.

### 4.5 Codegen from the IR (a later stage)

Once the IR carries everything codegen needs, LLVM emission can read the
IR instead of the token stream. That is the AST/IR boundary
COMPILER_INTERNALS.md calls the long-term direction. It is the last
stage, not a precondition (§9).

## 5. Evidence: the prototype

`tools/ncore/` is 2.4k lines of Python:

- a parser for the subset the probes use;
- the lowering (§4.1);
- the checker (§4.2–4.3);
- 70 declared stdlib summaries.

It never looks at a surface form after lowering. Run it with
`PYTHONUTF8=1 python tools/ncore/run.py --list tools/ncore/subset.txt`.

**Probe corpus.** 1,864 probes use no closures, traits, threads, `Rc` or
generic definitions. The prototype lowers 1,607 of them. The other 257 use
`defer`, fn types, results, globals or library files outside the core set,
and are reported as skipped.

| verdict against the probe's `// map:` line | probes |
|---|---|
| agree: refused, as the probe says | 639 |
| agree: runs clean, as the probe says | 642 |
| prototype accepts a probe that must be refused | 194 |
| prototype refuses a probe that runs clean | 132 |

That is **80 % agreement (1,281 of 1,607) from 900 lines of checker that
contain no case for any spelling**. Agreement grew as single rules were added in the checker
and applied to every spelling at once:

- a call's effects apply before its stores;
- a view read out of a field is a view of what is held there;
- a value block's tail lands in a temporary of the enclosing depth;
- a payload taken out of an owner moves it;
- the arguments of a call are frozen for its duration.

One rule moved up to 70 probes.

**Open holes.** Nine probes are written from open tickets: #428, #495,
#557, #580, #606, #832, #839, #842, #847 (`tools/ncore/openprobes/`). The
prototype refuses **all nine**, each at the read or the return that would
touch freed memory. nurlc on main (a8aca0ec, rebuilt) accepts eight of them,
and AddressSanitizer reports a heap-use-after-free in each. The ninth,
#428, is refused by nurlc in the spelling written here.

**What the disagreements are.** Almost all of them are nurlc semantics that
lie outside A2, which the prototype models only in part:

- handing a replaced value over to the binding that read it (#265);
- the keep rule `= o ( f o … )` (#475);
- a struct cursor as a copy of the struct (#781);
- clone-on-store and the implicit copies of a lend that escapes a join or
  a block;
- a struct whose field views a sibling field, moved or returned whole.
  This needs a `self` root in summaries.

These are exactly the rules §7 asks the owner to keep, formalise or retire.
Each is one rule in the engine, not one per spelling.

**Not claimed.**

- The prototype does not decide drops and does not generate code.
- It does not reach parity with nurlc.
- Its speed says nothing about the engine in NURL.

## 6. What the design closes

| family | closed by |
|---|---|
| S surface form | the core IR, by construction: there is one form |
| P path granularity | places in the analysis (§4.2) |
| L leaks / lost writes | one engine deciding drops and refusals (§4.4). A store into something that is not a place is visible in the IR. |
| M, callee known | summaries computed by the same analysis over the whole program |
| M, closures / `dyn` | needs D1 (§7) |
| same `Rc` | needs D3 (§7) |
| threads | the existing crossing rules, now applied to one IR |

From the classification: the core IR with places closes about 70–75 % of
the open unsound acceptances and 17 of the 25 open precision refusals.
Declared summaries on closure types and trait methods (D1) add about 11 %.
About 5 open holes need a language rule (shared `Rc`, two thread rules).

## 7. Decisions for the owner (language surface, rule 8)

- **D1. Closure types and trait methods carry a summary.** Inferred where
  the closure's flow is known; where a caller cannot know (a closure
  parameter, a `dyn` call) it reads the summary in the type. Alternative:
  a whole-program union of every closure that can reach a parameter. That
  is sound but imprecise; it is what #423 refuses today.
- **D2. `unsafe` / `raw` / FFI functions declare their summary in source**
  (§4.3).
- **D3. A shared `Rc` payload.** Which `Rc` handles alias is dynamic.
  Either a view of `rc_get` may not be held across a call that may reach
  that `Rc` type, or the payload carries a run-time borrow flag
  (RefCell-like; this costs run time, line 2).
- **D4. nurlc semantics outside A2.** For each of hand-over, keep rule,
  implicit copies, struct cursors and payload takes: keep it with a formal
  rule (claude-formal), or retire it before 1.0 (rule 7).
- **D5. A plain parameter that is changed.** It is read as `inout` today
  (a phase-C reading). Keep the reading as a summary effect, or require
  `inout` in source.

## 8. Formal

The engine's rules are A2's: `Eff.kills`, `CallT` against a summary, and
`FnOK`. A2 is per binding. Places are strictly finer, so the engine can
ship per binding first (sound by the existing proof) and add places as a
proven refinement.

To formalise:

- places;
- exits (`break`, `continue`, early `^`; README 147–158 already plans
  them);
- per-call ownership, encoded as DynCell;
- whichever D4 rules are kept.

The IR plus its summaries is the phase-C certificate input: a verified
checker reads the same thing the engine does.

## 9. Stages

The old checker stays the authority until the new one agrees with the
probes. Each stage is its own PR series.

| stage | content | gate |
|---|---|---|
| S0 (this PR) | proposal, reference checker, open-hole probes | none: docs and tools only |
| S1 | nurlc emits the core IR (`--emit-core`) from the fused walk, one emitter call per construct. No behaviour change. | `tools/tree_sweep.sh` byte-identical IR. The reference checker reads nurlc's IR and agrees with the probes it agrees with on its own. |
| S2 | the engine in nurlc, behind a flag, then the default | `holes/check.sh`: 0 holes and every `map` verdict. Corpus and goldens. Self-compile instructions no worse than today's walk. Then delete the `bck_*` walk. |
| S3 | drops and drop flags from the engine | leakgate, memgate, ASan corpus. Delete the `mem_*` decision code. |
| S4 | codegen from the IR | tree_sweep. ADR 0003 reopened only if a split then pays. |

**While S1–S3 land:**

- Nobody else edits the ownership parts of `nurlc.nu`.
- Hole tickets are frozen; their probes become the engine's tests.
- A new hole is filed as a probe.
- Work outside the compiler continues: stdlib, packages, runtime, formal.

## 10. Costs and risks

- **Compile time** (line 2): one dataflow over a compact IR replaces about
  30 passes and the row log. The walk is 28 % of a self-compile today.
  S2 is gated on instructions no worse.
- **Memory** (line 3): the IR is per function and is released after
  codegen.
- **Precision** (line 4): the 1,568 run-clean probes are the guard.
  Precision rules land in the engine once, for every spelling.
- **Long tail:** reaching parity on the remaining 20 % is real work, mostly
  the D4 rules. The prototype shows each is one rule.
- **Bootstrap:** S1 is additive, and S2 runs both checkers side by side
  before the switch.

## 11. Alternatives

- **A. Status quo.** Rejected by §2: about 60 holes a day opened and
  closed, with no trend down.
- **C everywhere** (declared signatures on every function). More burden
  than needed: inference over the IR is exact for known callees. Declare
  only where inference must union (D1, D2).
- **D. Second-class views** (no views across indirect calls). The smallest
  checker, but it breaks the most programs; it remains the lower bound if
  D1 is refused.
- **Dynamic checks everywhere** (generational references, run-time borrow
  flags). Sound by construction, but costs run time and memory on every
  view (lines 2 and 3). It is kept only as D3's option for `Rc`.

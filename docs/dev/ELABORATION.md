# Elaboration — producers land in a binding before anything consumes them

Status: **design, under review** (Agora #222). Nothing here is implemented
yet. Read [`COMPILER_INTERNALS.md`](COMPILER_INTERNALS.md) first: this note
assumes its picture of the fused walk.

## 1. Why

The probe family h740–h974 (Agora #179–#214, #205, #209) is one shape
repeated across surface forms. A value is produced by a **producer form**
and lands in a **consumer**:

| producer forms (value position) | consumers |
|---|---|
| a join: `?` / `??` | `:` let, `=` assignment (local, outer, `inout`, by-reference capture, field) |
| a value block `{ … tail }` | `^` return and the fall-off value |
| a try `\ ( f … )` | a call argument (borrowed, `sink`, kept by the callee, handed back) |
| a fall-off value | a struct / option / result / enum literal's field |
| (a return under `;` defers) | a `??` scrutinee, a join's arm, a statement that discards it |

The calculus has none of the producers in value position. In A2 a
conditional is a statement (`ite`) whose arms are assignments, a block is a
statement, a call names every argument (`letcall x f args`), and a
temporary is a binding its statement makes (formal/RULES.md, rows for
h371–h381 and h725–h732). nurlc lowers each (producer, consumer) pair at
the consumer's `gen_*` site. Every hunt found the next pair that was
missed, and each fix added another case to one of those sites. Of the 30
fixes for #179–#214:

- 12 changed `gen_ret`;
- 10 each changed `gen_match` and `gen_assign`;
- 9 changed `gen_agg_lit`;
- 7 changed `gen_call`;
- 5 each changed `gen_cond` and `gen_block_expr`;
- 4 changed `gen_fn_decl_concrete`;
- 3 each changed `gen_let_or_struct` and `gen_try_expr`.

The fixes communicate through side channels that each consumer re-reads in
its own way. `gen_ret`, for example, works out the "effective" shape of what
it returns (`ret_eff_tt`) by looking through a value block's tail
(`g_blk_tail_eff`, `g_blk_froot`, `__tail_first_tt__`) and a try's call.
Value blocks carry their own name-substitution log (`g_blk_lets`,
`__sx_close`, h216). Joins publish their arms' ownership and lends to
whoever reads them next (`__last_join_own__`, `__last_join_arm_lends__`,
`__last_join_lend_*`, `g_join_rdepth`, `g_join_flends`, `g_join_deep`).

This is N×M work: every new consumer must handle every producer and every
new producer must reach every consumer. The owner's line 1 asks for the fix
at the source. The source is the pairing itself. **Elaboration turns N×M
into N+M.** Each producer is lowered once, into a binding. Each consumer
handles only a name, which every consumer already does, by its
best-tested path.

## 2. The rule

> A producer form in value position is compiled as a **statement
> temporary**: a compiler-made binding `t` declared at the consumer's
> depth, which the form fills the way the calculus fills a binding. The
> consumer then reads `t` as if the source had named it.

What each form becomes, written as the calculus would have it (`t` fresh,
declared empty: no owner, nothing lent):

| form in value position | elaborated |
|---|---|
| `? c a b` | `: t` · `ite c (= t a) (= t b)` · consumer reads `t` |
| `?? s { P → a … }` | `: t` · a match statement whose arms end in `= t a` · consumer reads `t` |
| `{ stmts tail }` | `: t` · `{ stmts = t tail }` (the tail is an assignment to an outer binding) · consumer reads `t` |
| `\ ( f args )` | `: r ( f args )` · `?? r { Err e → ^ Err e  Ok v → = t v }` · consumer reads `t` |
| the fall-off value `tail` | `^ tail`. It has no form of its own: `gen_ret` already compiles it (`g_ret_implicit`). What it hands back is whichever form its tail is. |
| `^ v` under `;` defers | `: t v` · the defers run · `ret t`. The returned value is bound before any cleanup runs. |

Two existing rules then do the work that is spread over the consumers
today:

1. **Assignment to a binding shallower than the producer's own locals**
   (#179, #190: "hands it a value of its own"). A lend of an arm's or a
   block's local is copied, or refused when it cannot be. An owner the arm
   selects moves out on its path (`mem_arm_hown`). Every join and every
   value block now reaches this rule, so it is the one place that decides.
2. **A temporary is a binding its statement makes** (RULES row h378–h381;
   rows h725–h732 for joins). `t` rides the call-temporary journal. It is
   dropped right after the call that consumes it, or at the end of the
   statement when the consumer is not a call. It is moved when the callee
   keeps, consumes or hands it back. A view of it kept past its statement
   is refused, as for any call temporary today. The drop points are those
   of today's temporaries: nothing lives longer (owner's line 3).

A per-call ownership answer (#185, #186, #203, #205, #206) lands in `t`'s
drop flag. The consumer reads a binding whose flag says whether it owns.
That is A2's owner cell (`A2/DynCell.lean`) under a name, and it replaces
one fix per consumer.

## 3. Where in the pipeline

nurlc has no tree to rewrite before the borrow walk (COMPILER_INTERNALS §1),
and this design does not add one. The elaboration lives **inside the fused
walk, at the consumer's value start**. One entry point,
`elab_operand lex syms cg`, is called where a consumer would otherwise
peek at the next token and branch on its shape:

1. If the next token does not start a producer form, return and leave
   everything untouched. This is the common case. It costs one token-type
   comparison.
2. Otherwise compile the form as the elaborated statements above.
   - **Records** (what `bck_analyze` walks at the function's end): the
     walk sees the elaborated statements, not the form. The rows are
     `let t` (empty) before the form, `assign t` with the arm's or tail's
     reads at each arm or tail (still inside that arm's or block's scope),
     and then the consumer's own row reading `t`. That is "before the
     borrow walk" in the literal sense: the walk only ever sees let-bound
     temporaries.
   - **IR**: unchanged where it can be. A join's arms still meet in a
     `phi` of values and a `phi` of ownership bits (the copy-out-of-arms
     protocol). A block's tail still flows out as an SSA value. What
     changes is that the result is bound to `t` at the meeting point,
     with its flag. A scalar result (`i`, `b`, `f`, `u8` …, which in safe
     code is never kept or stored: Agora #134) gets no slot, no journal
     entry and no flag. `t` names its SSA value.
3. **Hand the consumer the name.** A one-token pushback,
   `nurl_lex_push_name lex t`:
   - shift the token window right by one slot;
   - when the fifth slot was filled, rewind the source position to that
     token's start (`TF_START`), so nothing is lost or re-lexed out of
     order;
   - write the current slot as an identifier.

   No per-access branch is added to the lexer. The consumer then runs its
   ordinary name path (`^ t`, `( f t )`, `= x t`, `@ S { f t }`).

Drop insertion is inline in nurlc (`mem_*`), so "before drop insertion"
means the same thing: every consumer's drop logic sees a named temporary,
never a form.

**Rejected alternatives:**

- **A token-rewriting pre-pass** (source to source before
  `parse_program`). The temporary's type is not known before type
  checking. Hoisting a join out of `( f ( g ) ? c a b )` would run it
  before `( g )`, and avoiding that means naming every earlier argument
  too, which is full A-normal form at real compile-time cost. Hoisting
  out of an arm also changes control flow. Walk-level elaboration keeps
  evaluation order for free: the earlier arguments are already SSA values
  when the form is reached.
- **A real AST/IR boundary.** That is COMPILER_INTERNALS' long-term
  direction, and the bootstrap fixed point makes it a big-bang change.
  This design is the step that fits the fused walk. It is also what the
  AST would do first, so it is not wasted.
- **A named-operand entry in each consumer** instead of pushback. It is N
  edits that each re-learn the consumer's peeks (`ret_first_tt`,
  `ret_first_val`, `__rr_pk` …). The pushback makes the consumer's own
  peeks see a name.

## 4. Diagnostics (owner's line 4: no worse messages)

- **Positions.** The form's tokens are compiled as before, so every error
  inside the form points where it does today. The rows `let t` and
  `assign t` carry the form's line and column. A walk error about `t`
  therefore points at the producer, and at the arm or tail that assigned
  it.
- **Names.** `t` never appears in a message. A statement temporary
  registers a display phrase in the walk's reverse map (`rv_<id>`), for
  example "the value of the `?` at 12:9" or "the value of the block at
  30:5". Messages that today say "this hands back, on one of its
  paths, …" keep their meaning. Where the generic name path words a
  diagnostic differently, the PR shows the before and after.
- **Gate.** The `.err` goldens and `tools/check_diag_coverage` must stay
  byte-identical, unless a stage's PR lists each changed message and why
  it is no worse.

## 5. What becomes dead

Per stage, these are the consumer-side cases and side channels that stop
having a reader. Line counts are from main at db510c8b.

| stage | consumer cases that go | helpers / channels that go or get one caller |
|---|---|---|
| value blocks | `ret_eff_tt`'s block branch in `gen_ret`; the `TT_LBRACE` cases in `gen_assign`, `gen_agg_lit`, `gen_let_or_struct`, `gen_call` | `g_blk_froot`, `g_blk_tail_eff`, `__tail_first_tt__`, `__tail_root_tt__`, `__tail_callee__`, `mem_blk_tail_copy_slot`, `mem_blk_tail_deeper_args`, the name-substitution log (`g_blk_lets`, `__blk_log`, `__blk_owner`, `__blk_val`, `__sx_close`, `__blk_tail_sx`): about 160 lines of helpers |
| joins | the `TT_QUEST` / `TT_QUESTQUEST` cases in `gen_ret` (7), `gen_assign` (6), `gen_cond` (6), `gen_match` (5) and the agg/call paths | the join channels every consumer resets before it reads its value (`gen_ret` resets 15 side channels before every `^`, 9 of them for joins: `__last_join_*`, `__last_phi_*`, `g_join_flends`, `g_join_deep`), `g_join_rdepth` / `g_join_flends` / `g_join_deep` as cross-consumer state, `__arm_src_depth`, `__arm_flends`, `__arm_froot`, `mem_join_copy_slot`, `mem_ret_join_own`, `mem_join_local_lend`, `__nc_join_local_lend`, `__join_lends_args_local`: about 360 lines. `mem_arm_hown` and `mem_arm_take_*` stay, now called only by the assignment path. |
| tries | `gen_try_expr`'s consumer-shaped branches; the `TT_BACKSLASH` cases in `gen_let_or_struct` (10), `gen_call` (5), `gen_ret` (4), `gen_assign` (4), `gen_agg_lit` (4) | `mem_ret_lends_as_call`'s try use, `__nc_wrap_payload*` |
| fall-off / defers | `g_blk_fall_value`; the defer special cases in `gen_ret` (`__jmove`'s `g_defer_count` exception) | — |

The inventory is a starting list, not a promise. Each stage's PR deletes
what its probes prove dead and keeps what still has a reader.

## 6. Compile-time cost (owner's line 2: no slower)

Measured with a scratch build of main that counts every join, match, try
and block by position and type class:

| | self-compile | `nurlapi/main.nu` |
|---|---|---|
| `?` in value position | 1,919 (442 scalar, 1,387 `s`, 90 void) | 548 (459 scalar, 89 owning or view) |
| `??` in value position | 0 | 185 (138 scalar, 47 owning or view) |
| value block outside an arm | 1 (void) | 0 |
| try `\` | 0 | 0 |

**Value blocks** are nearly free, since the self-compile has one. A stage
that changes nothing measurable on the self-compile is also the safest
place to prove the mechanism.

**Joins** carry the cost question. Per elaborated owning or view value, the
walk adds:

- one symbol definition;
- one journal entry, or none when the arms' ownership is static;
- one `let` row and one `assign` row per arm (arms record rows today too).

It removes:

- the per-consumer channel resets;
- the `mem_join_heads_stmt` / `g_blk_val_depth` value-position probing;
- the arm-depth bookkeeping each consumer redoes.

Scalars add nothing: no slot, no row, no journal entry. If every one of the
1,387 elaborated `s` joins in the self-compile cost as much as a source
`:` let, the self-compile would get under about 1 % slower before
counting what is removed. The joins stage is not merged unless
self-compile instructions are no worse (fair callgrind, same binary
location, null-change noise floor). Peak RSS must also be no worse
(memgate).

Emitted IR does not grow for scalars or for joins that already had an
ownership `phi`. A slot appears only where a `% Drop` value needs a flag,
which exists today in another form. LLVM's `mem2reg` removes it at the
optimisation levels nurlc builds with.

## 7. Staging: one form per PR, each provable on the probe corpus

| stage | content | proof |
|---|---|---|
| 0 | Infrastructure, no behaviour change: `elab_operand` (returns at once for every form), `nurl_lex_push_name`, statement temporaries on the call-temporary journal, the `rv_` display phrase | `tools/tree_sweep.sh`: byte-identical IR on the whole tree; self-compile instructions within the noise floor |
| 1 | **Value blocks** (the prototype): `^`, the fall-off value, `=`, call arguments, literal fields, `:`. First the let-then-name path is made sound for blocks (the twins below), then the consumers switch over. | the value-block twins agree with their probes; holes `check.sh`: 0 holes and every verdict in `map.tsv` unchanged; corpus unchanged; self-compile instructions no worse; the value-block helpers in §5 deleted |
| 2 | Joins `?` / `??` | as stage 1; the joins inventory deleted; cost gate above |
| 3 | Tries `\` | as stage 1 |
| 4 | Defers: the returned value is bound before cleanup | as stage 1 (h-probes of #197 and the `defer_*` goldens) |

Every stage also runs the usual gates: `./build.sh`, memgate, dcegate,
leakgate, `run_san_tests.sh` and `tools/metamorph/spellings.py`. A stage
deletes the consumer cases it makes dead in the same PR, so no stage leaves
two paths deciding the same thing.

### The oracle: elaborated twins of every probe

The elaborated program can be written in source, so each stage has a
mechanical oracle. `tools/fuzz/holes/elab.py` rewrites every probe whose
`^` or `=` consumes a producer form into its elaborated twin:

```
^ <form>      →   : __el <form>
                  ^ __el
= x <form>    →   : __el <form>
                  = x __el
```

The twin must get the same verdict as the probe. A twin that differs is a
gap in the let-then-name path. That is the path every consumer goes
through after elaboration, so a stage switches its consumers over only
once the twins of its form agree with the originals.

The first run (main 8946e8d1, the 27 probes whose `^` or `=` takes a value
block or a simple join) found 8 twins that differ, all from safe to
**HOLE**, and all 8 are heap use-after-frees. Minimising them also turned
up a leak:

- `: String t { … ( string_from … ) }` leaks the String: the binding
  never takes the tail call's ownership bit. `mem_udrop_bind_flag` looks
  through a block's tail only when that tail is a join.
- `: String t ? c ( string_from … ) ( string_from … )`, then `= o t` with
  `o` an `inout` parameter, is a use-after-free: `t` is still dropped after
  `o` took its buffer.

These are holes in today's compiler, filed on their own. They are also
the N×M pattern seen from the other side: the pairs fixed for `^ {…}`
and `= o {…}` were never fixed for `: t {…}` followed by `^ t` or `= o t`.

## 8. Phase C

The elaborated program is what a phase-C certificate would be about
(formal/README.md). The record stream after elaboration is A2's statement
language: `letv`, `assign`, `ite`, `letcall`, blocks. A certificate checker
can read it without knowing nurlc's surface forms, and the surface forms
need no rules of their own in the proof.

## 9. Open questions for review

1. **The `rv_` phrase.** Is "the value of the `?` at L:C" the right
   wording, or should a message name the consumer instead ("the value
   this `^` hands back")?
2. **The drop point of a temporary consumed by a non-call** (`^`, `=`,
   a literal field): the end of its statement, or right after the
   consumer? They differ only for a temporary the consumer neither moves
   nor keeps, which today is an arm of a discarded join. The proposal is
   the statement end, which is what the calculus's `letv … body` scoping
   gives.
3. **`??` scrutinees** (a producer as the thing a match takes apart).
   Elaborate them in stage 2 with the joins, or leave them to the match's
   own temporary rules (#182, #208), which already bind the scrutinee?

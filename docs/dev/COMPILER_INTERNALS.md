# nurlc internals — the map of the fused walk and its global state

This is the document to read **before changing the compiler**. It states
how `compiler/nurlc.nu` is organised, which process-global tables exist,
who writes them, and which invariants keep the single fused pass honest.
The critique this answers (critic M2) was fair: the type rules live
inside the code generators, so without this map every change begins as
archaeology. The map is the pragmatic first step; a real AST/IR boundary
remains the long-term direction and is deliberately **not** attempted in
one leap — the bootstrap fixed point makes big-bang refactors expensive
and every incremental step here is gated (see §5).

## 1. Shape

`compiler/nurlc.nu` is **one self-contained file** (no `$`
imports — it defines its own string/symtab/lexer helpers so stage0 can
build it from `nurlc_lastgood.ll` with nothing but clang). Why it is not
split into modules of its own either:
[ADR 0003](../adr/0003-one-file-compiler.md). There is **no
AST**, and the one IR data structure, the core IR (below), is built beside
the walk and read only by `--emit-core` and `--engine`: parsing, type checking, borrow checking
and code generation are one recursive descent (`parse_program` →
`gen_stmt` / `gen_expr` / `gen_*`) that **emits LLVM IR text to stdout
as it walks** (`emit` = `nurl_print`). What crosses statement/function
boundaries is not a tree — it is the global state in §3.

Consequences to internalise before editing:

- A "type rule" usually lives at the `gen_*` site that lowers the
  construct, next to the IR it emits. Changing a rule = finding every
  gen-site that encodes it.
- Nothing can be re-walked. Anything needed *later* must be recorded in
  a table *now* (that is what most globals are).
- Output order is emission order. Deferred definitions (closures,
  generic instantiations, drop thunks, DWARF metadata) are queued in
  tables and flushed at safe points.

## 2. Pipeline

```
main()
 ├─ CLI flags → g_borrowck / g_strict_borrowck / g_dbg_enabled / g_lint …
 ├─ allocate ~20 sym tables (fresh per process; nothing survives runs)
 ├─ nurl_print_buf_start            — the whole module is emitted into
 │                                    one buffering frame, not straight
 │                                    to stdout (see dce_emit_module)
 ├─ scan_type_names      (prepass)  — struct/enum names → kind table
 ├─ scan_generic_structs (prepass)  — generic struct templates → tables
 ├─ scan_fn_sigs         (prepass)  — explicit fn/method signatures + trait
 │                                    contracts, follows `$` imports
 ├─ read_type_layouts              — declared fields and enum payload storage
 ├─ resolve_trait_impls            — verify associated bindings and register
 │                                    defaults against the complete trait table
 ├─ emit_header                     — module preamble, runtime declares
 ├─ verify_super_obligations       — require each implemented supertrait
 ├─ scan_dyn_types       (prepass)  — %Trait dyn-object vtables needed
 ├─ lazy_reach                      — library functions (stdlib/, deps/)
 │                                    nothing reaches are skipped by the
 │                                    walk below (off under --no-dce,
 │                                    --lint, -g; NURL_LAZY_TRACE)
 ├─ parse_program                   — THE fused walk (parse + typecheck
 │                                    + borrowck + memdrop + IR emit,
 │                                    one function at a time; deferred
 │                                    closures/generics flushed between
 │                                    top-level items)
 ├─ emit_pending_drop_graphs        — drop definitions after complete layouts
 ├─ resolve_sink_summaries           — fixed point of parameter consumption
 ├─ emit_sink_flags                 — static ownership decisions for LLVM
 ├─ resolve_pending_escapes         — replay escape checks parked on
 │                                    forward/generic calls
 ├─ dbg_flush                       — queued !DI* metadata (--g)
 ├─ lint_report_unused_*            — --lint reports
 ├─ exit non-zero if g_err_count / g_bck_errors
 └─ dce_emit_module                 — stop the buffer; write out the
                                      globals plus the functions `main`
                                      can reach (--no-dce: all of them)
```

The `scan_*` prepasses and deferred trait resolution exist so the fused walk
never needs a second look at the source: by the time `parse_program` runs,
every signature, type name, template and dyn-trait requirement is already in
a table.

The ordinary signature prepass records every `inout` parameter's position in
`g_fn_inout`, just as generic template registration does. Forward calls and
mutually recursive functions therefore use the same address ABI as calls after
a definition. Never infer that ABI from definition order.

Function identities in semantic tables remain source names. LLVM emission
uses `llvm_source_fn` for definitions and `llvm_call_fn` for references, after
the signature prepass has recorded source functions and external declarations.
Programs place ordinary functions in the `__nurl_fn.` namespace so names such
as `open` and `strlen` cannot collide with libc or acquire its optimizer
semantics. Explicit external declarations, `--keep` roots and no-main modules
retain their external ABI; the existing main wrapper remains unchanged.
Calls, function addresses, methods, deferred drop bodies and vtables must all
use this boundary. Diagnostics and DWARF keep readable source names.

The borrow-checker records a `defer` block as a registration, with a synthetic
arming slot in its existing ownership state. It skips the body on normal flow
and checks definitely armed bodies in reverse order at each return and normal
function exit. A consuming call in deferred cleanup must not mark its argument
moved at registration. As with conditional moves, the default checker does not
diagnose a cleanup whose arming state is uncertain after a branch join.
After each body, the checker revisits the newest armed site: nested cleanup
registered by that body runs before older defers. Code generation builds a
child cleanup chain against the previous top and restores the parent's entry
as the enclosing top; an unreached parent skips its entire child chain.

With `--check`, the complete fused walk and deferred checks still run; main
unwinds the output buffer without making the final module copy or invoking
DCE/splitting, then follows normal cleanup.

The frontend pipeline runs inside journalled recovery. Main owns its source,
codegen state and global tables outside that recovery extent and releases them
on both success and diagnostic failure. Lexers and scoped symbol tables are
also linked into the compilation context (`g_live_lexers`, `g_live_symtables`):
normal release unlinks an instance in constant time, and final cleanup drains
instances abandoned by a diagnostic. Per-declaration recovery restarts the IR
buffer after discarding incomplete output. Compiler error-path leak coverage
is still incomplete; the outstanding failures are recorded in
[`V1_HARDENING.md`](V1_HARDENING.md).

`dce_emit_module` is the only stage that looks at the emitted IR as
*text*. It indexes every `define … }` block, marks the ones reachable
from `main` (roots: `main`, plus anything named between blocks — a
`@__vt.…` vtable constant names its thunks at module scope), and prints
the live sub-sequence. Working on the finished text rather than a
source-level call graph is what keeps it indifferent to how a function
came to exist: closures, monomorphisations, drop glue and dyn thunks are
all just `@name` references by then. Normal output only drops unreachable
definitions. With `--sanitize-address`, `__ir_write_function` inserts the
ASan function attribute as each indexed range is written. The same boundary
writes split definitions, including replicas; it neither shifts the index
nor allocates another module buffer. Dropping something still referenced
surfaces as an undefined symbol at link time.

### What the emitted IR promises the optimiser

nurlc emits first-class aggregates (`%Point`, `%Shape`, `{ i1, T, E }`)
as SSA values, and LLVM is good at them along a straight line. Two shapes
it cannot see through, so nurlc does not emit them (AGORA-853;
`compiler/tests/agg_no_phi_ir.sh` holds both):

- **No `phi` that merges aggregates.** InstCombine folds an
  `extractvalue` into a phi only when it is the phi's one user, and an
  aggregate has a user per field: the tag of such a phi, or an option's
  flag, stays an `extractvalue` no jump threading or value propagation
  reads. A value join (`?`, `??`) of an aggregate type therefore goes
  through a slot of the frame — each arm stores before its `br`, the
  join loads after its phis (`__agg_slot_*`; gen_cond's `c_jslot`,
  gen_match's `m_jslot`) — and SROA + mem2reg give one scalar phi per
  field. A function or closure body whose result is an aggregate returns
  the same way: its `^` sites, the try's error exit and the fall-off
  value store into the result slot and branch to one exit block
  (`emit_ret_value`, `emit_agg_exit`, `__agg_ret__`), because several
  `ret %Agg` are merged by SimplifyCFG into exactly the phi this avoids.
  What "aggregate" means here is `__ll_is_agg`: more than one word. A
  String, a Vec, a library handle, a struct of one such field and an
  enum of bare tags are one word under another name, their phi folds,
  and they keep it.
- **No load of an immutable tag.** An enum variant is its place in the
  declaration, printed as that number (`<Variant>__tag`,
  `__variant_tag`; its `__global` mark is `=<tag>`, so reading one costs
  the lookup a global's read already made). There is no `@Variant`
  global: a load of a global is opaque until LTO internalises it — after
  the pre-link inliner and jump threading have run.

Three returns keep a `ret` of their own. A tail call's result
(`g_tail_reg`) has to stand beside the call for the recursion to become
a loop. The body's last statement, when no return before it took the
slot (`g_ret_top`, `g_ret_final`, `g_agg_ret_n`), is the only exit of a
body that has no other: it compiles to the IR it always did, with no
slot and no exit block. And anything that is no aggregate. The slot is
the function's result slot (`__ret_val__`, `__ret_slot`), the one a
return under a `;` defer already leaves its value in; a closure body,
which has no defers of its own, gets one from its first return that
needs it.

(A join one of whose arms returned keeps a phi of its one remaining
edge, which merges nothing and LLVM reads as its value. A temporary's
drop word carried past a `?`, `mem_join_drop_words`, is a phi of a
one-word handle beside its flag.)

A new emission site that merges values of a possibly-aggregate type takes
the slot (`__ll_is_agg` decides), never a hand-written `phi`.

### The core IR

The walk also builds, per function, the core IR of
[PROPOSAL_CORE_IR.md](PROPOSAL_CORE_IR.md): variables and statements in
evaluation order, every producer bound before its consumer
(`g_core_*`, the `core_*` functions). `--emit-core` prints it, and the
ownership engine reads it under `--engine` (in shadow). [CORE_IR.md](CORE_IR.md) says how it is built (an
operand stack `gen_expr` checks where it returns) and what a new
expression form owes it: a hook, or `compiler/tests/core_ir.sh` fails on
the `opaque` it leaves.

## 3. Global state — families and owners

Globals fall into the families below. The generated appendix (§6)
lists every one with its writers; this section is the mental model.
"Sym table" below = the compiler's own scoped string→string map
(`nurl_sym_new/def/get`, push/pop for scopes; `strdup` on both def and
get — returned values are owned copies).

| family | key globals | role & lifetime |
|---|---|---|
| input snapshots | `g_input_source`, `g_input_key`, `g_source_snapshots` | stdin overlay borrows main's live source/key; ordinary reads cache their first bytes by canonical path for this invocation; `compiler_read_source` returns owned copies to every replay/diagnostic reader, and main frees the cache |
| diagnostics | `g_err_count`, `g_diag_recover_active` | error count + multi-error recovery mode; whole run |
| codegen cursor | `g_str_idx`, `g_did_ret`, `g_ret_forbidden`, `g_in_match_arm`, `g_defer_count`, `g_stmt_line/col/bare_*` | per-statement/-function flags; must be reset on the boundaries that own them (grep their writers before trusting a reset) |
| **last-type channel** | `g_last_type_ptr` | the expression walk's implicit return value: every `gen_expr` sets it; the *caller* reads it. Signedness is carried **in the type string itself** (`u8`/`u16`/… stay distinct from `i8`/`i16`/… in this channel; readers use `ty_is_unsigned`, emission normalises via `nurl_llty`) — the former separate unsigned flag was removed in the A1 rework; see the comment at `nurl_set_last_type` |
| string literals | `g_str_syms`, `g_str_idx` | interned literal metadata, flushed as module constants |
| generics | `g_generic_syms`, `g_generic_struct_syms`, `g_struct_inst_syms` | stored templates (token streams) + emitted-instantiation dedupe; whole run |
| traits/impls | `g_trait_syms`, `g_impl_{ret,name,trait,pos}_syms` | method dispatch keys `method##llvm_type` → return type / mangle / owning trait / declaration site (coherence) |
| pending trait contracts | `g_trait_pending` | one record per source impl, effective source snapshots and per-file diagnostic cursors; resolved after `scan_fn_sigs`, snapshots/cursors released before body emission; seen keys dedupe import replay |
| dyn traits | `g_dyn_needed`, `g_dyn_flat_*`, `g_super_obligations` | accumulator strings (not tables): vtables to emit + supertrait proof obligations |
| closures | `g_closure_defs/types`, `g_func_count`, `g_type_count`, `g_*_emit_base` | deferred closure bodies/types; the `emit_base` watermarks make the between-items flush idempotent |
| result types | `g_res_type_syms` | `! T E` lowering metadata for try-propagation checking |
| borrow checker | `g_bck` (per-fn record list + `warnset` + `ml_*` lines), `g_bck_depth`, `g_bck_closure_depth`, `g_bck_errors` | statements are RECORDED during the walk, analysed at function end (`bck_analyze` → `bck_walk_seq` over a byte-per-binding lattice array; names are interned to dense ids at `bck_explode`, `rv_<id>` is the reverse map for diagnostics) |
| escape analysis | `g_fn_inout/sink/escapes/invoke_only/ret_param`, `g_pending_escape` | interprocedural summaries; `g_pending_escape` holds checks parked on forward/generic calls, replayed by `resolve_pending_escapes` |
| auto-drop | `mem_*` journal (function-local handles) + `g_auto_drop_strings` | owned-resource journal driving scope-exit frees |
| DWARF | `g_dbg_*` | metadata id allocator + queued `!DI*` blobs; only live under `--g` |
| lint | `g_lint*` | usage recording; only under `--lint` |
| core IR | `g_core_*` | the function being lowered: statement words, variables, places, the operand stack, the temporaries not yet released; the printed module. Idle (`g_core_live` 0) without `--emit-core` |
| visibility/modules | `g_vis_syms`, `g_pending_pub` | import graph + pub tracking for cross-file access checks |
| module emission | `g_dce_*`, `g_split_*`, `g_sanitize_address` | buffered module, live-function index, partitioning and ASan attribute policy; whole run, written at final emission |

Reset discipline: everything is initialised in `main()` and the process
compiles exactly one program — **there is no reuse between files**
except via `$` imports walked in the same run. If you add a global,
initialise it in `main()` next to its family and document the writer
set in the appendix (regenerate it — §6).

## 4. Memory discipline

Address ownership now has a compilation-owned dependency graph (`origin_*`).
Each binding has a stable node; assignments add edges, so a loop backedge does
not lose a dependency whose parameter origins are still unknown. Calls add
conditional edges gated by a callee's returned-root or consuming parameter.
A worklist propagates inline 64-bit sets with sparse overflow words for larger
arities. Lifted closure parameters and hidden capture inputs have their own
index domain. Root-buffer identity is separate from embedded-reference facts:
releasing a new closure environment does not release the objects it references.
The existing diagnostic implications and graph facts converge together before
emitting private argument-drop constants. LLVM folds those constants at normal
optimization levels. Graph nodes, edges and overflow words are released by the
compilation context on successful and rejected compilations.

Temporary consumers have no helper-name whitelist. Each argument's sink,
returned-address, embedded-reference and unverified-call facts decide whether
the caller may release it. An aggregate result does not itself retain its
inputs; a scalar result does not prove that it discarded their addresses.
Unknown foreign and indirect calls propagate retention through source wrappers
in the lifetime-only `g_fn_unverified` summary, independently of diagnostic
escape contracts.

Primitive effects are read from the actual emitted LLVM declarations. Pointer
parameters need `nocapture` and `nofree`; a `readonly` function may instead
return an alias, which is recorded in the address graph. Terminal calls such as
`nurl_panic` use the unwind journal and do not promise `nofree`. These attributes
use the [LLVM 15 contracts](https://releases.llvm.org/15.0.0/docs/LangRef.html#parameter-attributes).
The custom function attribute `"nurl.value-only"="1 3"` records zero-based scalar
argument positions whose audited primitive role is data, such as a length or
allocation size. An integer type alone grants no such contract: it can carry
an address. Source definitions do not inherit a same-named primitive's effects;
user FFI declarations remain unverified unless an actual primitive contract
applies. This metadata does not add source-language FFI syntax.

A mutable string initialized from a proved owned local receives its own copy,
so later assignments can release replacements and joins can preserve previous
values. Borrowed parameters, guarded results and opaque casts retain their
identity; the spelling `s` alone does not authorize copying an address as text.

The compiler used to allocate arena-style — temporaries were simply not
freed. As of 0.30.0 **the self-compile leaks nothing**, and
`tools/leakgate.sh` (CI, zero tolerance) is what holds that. The
invariant that made the arena era safe still holds and still must not
be broken:

- `nurl_str_slice` / `nurl_str_cat*` / `nurl_sym_get` **always return a
  fresh owned allocation**. Emitted auto-drop frees a string temp that
  is passed *directly as a call argument*, so returning a borrowed
  pointer (e.g. a suffix of the input) is a use-after-free / invalid
  free waiting to happen. This was measured, attempted and reverted —
  see the M1 commit; `nurl_llty`'s comment documents the same hazard.
- The way to save memory is still **algorithmic, at call sites**: walk
  strings by index instead of re-slicing remainders, through a pointer
  hoisted once and a length measured once (`: *u txt_p # *u txt`, then
  the compiler-local `( nurl_str_at txt_p n i )`, in an `unsafe`
  function; `__norm_int_lit` is the pattern). `nurl_str_get` in a loop
  re-measures the string from its start on every call, which is
  quadratic; nurlc warns when that string is a binding made outside the
  loop. Build outputs in one exact-size buffer instead of
  concat-accumulating.
- What the campaign changed is that a helper's result is now *collected*
  rather than abandoned, which is a property of its **ownership
  summary**. Three ways to lose it, all of which cost real memory
  before: returning `^ # s ( strdup … )` so the cast hides freshness
  from return-site inference (declare the function `__ret_owned`);
  losing a forward call's dynamic ownership proof before its consumer
  captures it; and a mixed join — a borrowed parameter on one arm, a
  tracked local on the other — which vetoes the marker for the whole
  function. If you add a string-returning helper, check `leakgate` before
  you check the clock.
- History (self-compile peak RSS): 13.6 GB → 366 MB (borrow-checker
  state-map rewrite) → 125 MB → 115.9 MB (lattice-array rewrite) →
  **18.5 MB** (ownership campaign) → 24 MB (the module buffer the
  dead-function pass needs). `tools/memgate.sh` (CI) keeps it from
  regressing; if the gate fires on your PR, instrument first —
  per-site counters over `nurl_str_slice`/`str_skip_word` call sites
  found the last one in two runs.

## 5. Changing the compiler safely

The ownership walk's dense state string also has a control-flow bottom value,
`!`, meaning no continuing path. `bck_walk_seq` produces it on a return and
stops that path. `bck_join_state` excludes it, so a release followed by return
cannot become a loop-carried move. Explicit conditional else edges and match
arm boundaries cover both bare expressions and brace blocks. Match ownership
remains isolated per arm to avoid conflating payload bindings; only all-arm
termination propagates to its caller.

1. `./check.sh compiler/nurlc.nu` — fast frontend syntax/type gate.
2. Build and self-compare: the OLD binary and your NEW binary must emit
   **byte-identical IR for the same source** unless your change is
   *supposed* to alter codegen (then goldens move and you explain why).
3. `./build.sh` — bootstrap fixed point (stage1 ≡ stage2) + the full
   golden corpus. Borrow-checker changes: the `borrow_*` goldens are
   the behavioural spec.
4. `./tools/memgate.sh` — the peak-RSS budget.
5. `./tools/dcegate.sh` — proves the dead-function pass still drops
   unreachable code AND still keeps the indirect routes (dyn vtable
   thunks, `% Drop`, closures, monomorphs). The corpus catches only the
   second half: a pass that kept everything would stay green.
6. `./tools/leakgate.sh` — the self-compile must leak nothing. Needs a
   `./build.sh --san --no-tests` first; zero tolerance, no budget.
7. Sanitizers run in CI (`build.sh --san` + `run_san_tests.sh`) — run
   locally when touching drop/ownership codegen.

## 6. Appendix — every global and its writers (generated)

Regenerate after adding/renaming globals:
`python3 tools/gen_globals_map.py` (rewrites this section in place).

| global | declared | written by | holds |
|---|---|---|---|
| `g_agg_arg_lend` | :4323 | `mem_arg_consumption` | 1 while the call argument being compiled is an aggregate literal its callee may hand back whole (gen_call); ge |
| `g_agg_fpfx_st` | :4037 | `__gen_field_store_body`, `__mb_tmp_flag` | Where a struct literal generated now goes (gen_agg_lit's agg_fpfx): 0 bound by a name, 1 a path not known, 2 t |
| `g_agg_ret_n` | :1968 | `__csv_has`, `emit_ret_value`, `resolve_clone_hooks` | How the returns of the body being compiled reach its exit (emit_ret_value): how many stored an aggregate into  |
| `g_alias_tab` | :25015 | `__alias_tab` | The aliased imports' table (see __import_eff_src): the lexer reads a module's second spelling from it. 0 until |
| `g_alp_n` | :3979 | `__roots_have_param` |  |
| `g_alr_n` | :3972 | `__payload_of_frame` |  |
| `g_amv_cur` | :49777 | `bck_is_heap_lty` | Phase 2: an immutable `: T b a` whose RHS is a bare identifier naming a non-parameter heap binding moves `a` — |
| `g_amv_src` | :49778 | `bck_is_heap_lty` |  |
| `g_arcp_any` | :2926 | `__arcp_note` | Whether any callee takes an Arc (`arcp##`, §6.5), and whether the function being compiled has handled one (gen |
| `g_arg_dyn_box` | :2623 | `gen_dyn_construct`, `mem_arg_consumption`, `mem_arg_temps` | An argument that is `( dyn Trait v )`: the box is a temporary of the call (mem_arg_temps); gen_dyn_construct s |
| `g_arg_ident_log` | :2150 | `__vb_gone_check`, `mem_arg_consumption` | --strict-borrowck only: every binding NAME read while generating the current call argument, including reads ne |
| `g_arg_join_set` | :2659 | `mem_arg_consumption`, `mem_arg_temps` | Set when a `?` / `??` argument's ownership bit waits in `__argtmp_joinown__` for mem_arg_temps (agora #174): t |
| `g_arg_litown_set` | :2654 | `mem_arg_consumption`, `mem_arg_temps` | Set when a literal argument's owned fields wait in `__argtmp_litown__` for mem_arg_temps: the symbol is writte |
| `g_arm_fresh` | :4210 | `mem_arm_hown`, `mem_arm_hown0` | Did the arm mem_arm_hown last answered for take a payload out of an enum? |
| `g_arm_qval` | :4331 | `emit_agg_exit`, `emit_or_chain` | 1 from gen_match to the `?` / `??` that is an arm's whole value, in a match whose value is taken: that join's  |
| `g_arm_valu` | :4327 | `emit_agg_exit`, `emit_or_chain` | 1 while mem_arm_hown asks about an arm of a join whose value is taken (gen_cond's c_valu, gen_match's m_val):  |
| `g_at` | :106216 | `__ext_calls_back` | ── Which functions run inside a recover extent ───────────────── |
| `g_auto_drop_strings` | :3803 | `__target_arch` | Phase 2B auto-drop-strings feature flag. Default ON. Compiler's own source uses patterns (strings stored via n |
| `g_av_all` | :622 | `eng_fn_begin` |  |
| `g_av_none` | :444 | `eng_fn_begin` |  |
| `g_bck` | :2238 | `__target_arch` |  |
| `g_bck_ab_any` | :2965 | `bck_analyze`, `bck_borrow_begin`, `bck_walk_seq` | Whether any borrow of this function's walk is one of a payload (`ab_`). |
| `g_bck_ah_any` | :2969 | `__ah_mark`, `bck_analyze` | …and whether any owner of its walk holds views of one (`ah_`): a Vec, a map, a struct a payload view was store |
| `g_bck_ajn` | :2642 | `__bck_arm_join` | The value `?`s whose arms' stores are kept apart (agora #757, __bck_arm_join): a counter for their ids, and ho |
| `g_bck_ajp` | :2646 | `__bck_arm_join`, `__bck_flush_arm_joins`, `bck_fn_begin` |  |
| `g_bck_ans_union` | :198 | `bck_defer_fn` |  |
| `g_bck_bind_owns` | :47574 | `__shadow_reset`, `__word_count`, `bck_flush_moves` | …and 1 while gen_let records a binding that owns its value — not one a call lent it (g_bck_rhs_lend), whose dr |
| `g_bck_bind_scalar` | :47560 | `bck_flush_moves` | Set by bck_record_binding for its row: 1 when the binding holds no heap value and no address (a scalar), so no |
| `g_bck_bind_sown` | :47591 | `__assign_result_lent`, `__shadow_reset`, `bck_flush_moves` | …and 1 when it is an `s` that owns the buffer it points at (field 5 `o`): a tracked owned string, every assign |
| `g_bck_bind_udrop` | :47567 | `bck_flush_moves` | …and 1 when an owner that may hold views (class 3) holds a value with a `% Drop` of the program's own that may |
| `g_bck_bind_wview` | :47562 | `bck_flush_moves` | …and 1 when that view owns nothing (field 5 `w`, bck_record_binding). |
| `g_bck_br_next` | :4110 | `bck_walk_seq` | What the borrow a borrow row begins is a copy of (bck_byte_root), handed to bck_borrow_begin; -1 for none know |
| `g_bck_brev_id` | :4114 | `bck_analyze`, `bck_br_event` | The binding whose `let` / `=` row the walk is in, and what it was a copy of before that row (bck_br_event): th |
| `g_bck_brev_prev` | :4116 | `bck_br_event`, `bck_br_set` | (-2: not read yet — read at the event's first mark, bck_br_set.) |
| `g_bck_brw_on` | :2299 | `bck_note_borrow`, `bck_note_moved_field`, `bck_record` | Whether bck_note_borrow puts a source expression (g_bck's `brwsx`) on the borrow row it records (field 8), for |
| `g_bck_bvr_any` | :4089 | `__bck_enders_note`, `bck_analyze` | 1 once a call's row of the function walked ended a binding (`bvr_`, __bck_enders_note): only then is there ano |
| `g_bck_bxf_any` | :4033 | `bck_analyze`, `bck_borrow_transfer` | …and whether it has moved a borrow onto a field path (`bxf_`, bck_borrow_transfer's direct mode): its owner's  |
| `g_bck_cap_names` | :2172 | `__csv_has`, `bck_clear_cap_name`, `bck_fn_begin` | Names of `:`-bound closures in the CURRENT function whose capture list is non-empty — the allocation-free pre- |
| `g_bck_cap_via` | :2183 | `__csv_has`, `bck_defer_fn`, `bck_fn_begin`, `bck_opaque_param_run` | `<handle> <closure>` pairs for the current function: which closure binding made a captured handle reachable at |
| `g_bck_close` | :52937 | `bck_kill_stored_in_d` | The close marker of every open marker, found once per walk with a stack per bracket kind: the walk asks for th |
| `g_bck_closure_depth` | :2374 | `__csv_has` |  |
| `g_bck_cv_leaf` | :47613 | `bck_walk_seq` | Set while the walk asks what a value stored into a closure's capture views (bck_sx_name's `cv_` leaves; agora  |
| `g_bck_cw0` | :4067 | `bck_cursor_watch` |  |
| `g_bck_cw1` | :4068 | `bck_cursor_watch` |  |
| `g_bck_cw2` | :4069 | `bck_cursor_watch` |  |
| `g_bck_cw3` | :4070 | `bck_cursor_watch` |  |
| `g_bck_cwn` | :4066 | `bck_cursor_watch` | …and the ids a row may concern them through (bck_cursor_watch): up to four in `g_bck_cw0`…`g_bck_cw3` (`g_bck_ |
| `g_bck_dep_ret` | :4388 | `__ret_blk_exit_flush`, `bck_fn_begin` | (…and whether the function has any such return by dependencies — what bck_local_source asks of an owner a clos |
| `g_bck_depth` | :2247 | `__bck_arm_block`, `__csv_has`, `__ret_blk_exit_flush`, `bck_block_enter` +2 |  |
| `g_bck_dg` | :2244 | `bck_add`, `bck_add_word`, `bck_put` | A digest of g_bck's content, kept while a loop is walked (bck_put): the XOR of one hash per key and value, so  |
| `g_bck_dlx_line` | :2349 | `bck_join_giveback` |  |
| `g_bck_dlx_p` | :2348 | `bck_join_giveback` |  |
| `g_bck_dser` | :4418 | `bck_alias_step` |  |
| `g_bck_end_elem` | :4086 | `bck_borrow_sweep` | 1 while bck_view_end ends the views recorded of an owner for a buffer of one of its ELEMENTS moving (a view ta |
| `g_bck_end_eonly` | :4074 | `__bck_fe_moved_out`, `bck_borrow_sweep`, `bck_cursor_edit` | Set while a borrow end comes from elements dropped or replaced (not the value itself): an owner holding a clos |
| `g_bck_end_fcx` | :4098 | `bck_borrow_sweep` | …and the cursor of the `~` loop whose own element's buffer moves (`fcx_` of the element the change went throug |
| `g_bck_end_predefer` | :47585 | `bck_join_giveback` | While bck_end_post_defer ends what an exit releases before its defers: whether the caller's storage is left vi |
| `g_bck_end_thru` | :4094 | `bck_borrow_sweep` | 1 while bck_borrow_end ends the borrows of an owner for a change made THROUGH a borrow of one of its elements  |
| `g_bck_end_views` | :195 | `bck_join_giveback` |  |
| `g_bck_end_wid` | :4100 | `bck_borrow_sweep` | …and that borrow itself (bck_br_survives): -1 for none. |
| `g_bck_end_wroot` | :4078 | `__bck_fe_moved_out`, `bck_borrow_sweep` | …and, when the elements changed through a borrow, what that borrow's bytes are a copy of (bck_byte_root): a bo |
| `g_bck_ending` | :47577 | `bck_join_giveback` | The ids a scope's end has released so far, as it releases them (bck_scope_drop): dropped already, not after wh |
| `g_bck_epy_any` | :4045 | `bck_handle_match` | A `??` arm's payload read in place out of a program enum's binding (`epy_` + owner: the payloads, bck_handle_m |
| `g_bck_err_note` | :47581 | `__bck_dlx_note`, `__bck_inv_src_read`, `bck_note_may_own`, `bck_walk_seq` | A sentence the next borrow-check error ends with (bck_emit_error): what the read it names is, where that is no |
| `g_bck_errors` | :2378 | `__ptr_stale_warn`, `__ptr_stale_warn_at`, `bck_note_may_own` | capture hooks no-op so closure statements do not inline into the enclosing function's list (so closure scopes  |
| `g_bck_fe_live` | :4059 | `bck_analyze`, `bck_walk_seq` | …and how many `~` loops are being walked: only inside one can a borrow's end reach a loop's element (`feb_`, b |
| `g_bck_fep_any` | :4062 | `__fe_owner_note`, `bck_analyze` | …and whether one was filed under a path (`feoallp`, __fe_owner_note): the end of a binding holding that path e |
| `g_bck_fevar` | :2567 | `bck_block_enter`, `bck_fn_begin`, `gen_foreach` | A `~ x xs` loop's element binding is waiting for its body's block row (`pending_fevar` in g_bck names it). |
| `g_bck_fmv_any` | :4401 | `bck_analyze`, `bck_walk_seq` | Whether a callee took a field path in the function being walked: its ids, one a word, are g_bck's `fmv`, asked |
| `g_bck_fn` | :196 | `__bck_answers`, `__csv_has`, `bck_defer_fn` |  |
| `g_bck_fq` | :4233 | `bck_walk_seq` | The order field readers were bound in, for bck_fview_take (agora #387). |
| `g_bck_fv_any` | :4235 | `bck_analyze`, `bck_walk_seq` | Was a field viewer (`fb_`) bound in this function at all? |
| `g_bck_gen` | :2340 | `bck_analyze` |  |
| `g_bck_has_borrow` | :51770 | `__bck_fe_cursor_bind`, `__fe_owner_note`, `bck_analyze`, `bck_borrow_begin` +2 | Set once a function records a borrow: only then does the walk compare states row by row to end borrows whose s |
| `g_bck_has_cursor` | :4023 | `bck_analyze`, `bck_handle_match` | …and whether it has bound a `??` arm's payload as a cursor over the option binding it matched (bck_handle_matc |
| `g_bck_has_cv` | :47614 | `bck_analyze`, `bck_walk_seq` |  |
| `g_bck_has_defers` | :2346 | `bck_analyze` |  |
| `g_bck_has_deps` | :4006 | `bck_analyze`, `bck_dep_add` | Whether this function's walk has recorded any view dependency (bck_dep_add), and statement `vpass` rows pendin |
| `g_bck_has_paths` | :51772 | `bck_alias_step`, `bck_analyze` | Set once a function interns a field path (`s.items`, bck_intern). |
| `g_bck_hc_any` | :4026 | `bck_analyze`, `bck_walk_seq` | …and whether it has marked a borrow a copy of an owner's own handle (`hc_`, bck_view_end_via): a `let` clears  |
| `g_bck_held_any` | :53521 | `__bck_seed_held`, `bck_analyze` | 1 once the function walked has a parameter's pseudo (__bck_seed_held): only then can a holder hold a copy of a |
| `g_bck_hn_any` | :53525 | `bck_analyze`, `bck_sx_handle_mark` | 1 once the function walked has a copy of an element's handle among its sources (`~^id`, bck_sx_handle_mark): o |
| `g_bck_hr_any` | :4042 | `__bck_hr_set`, `bck_analyze` | …and once a binding was marked a copy of another's handle or a part of one (`hr_`, __bck_hr_set): a `let` clea |
| `g_bck_inew` | :4419 | `bck_alias_step` |  |
| `g_bck_inn` | :2344 | `bck_alias_step`, `bck_analyze` | intern table — bumped per bck_analyze so entries from earlier functions read as misses without any table clear |
| `g_bck_inp_any` | :4404 | `bck_analyze` | …and whether it has an `inout` parameter (g_bck's `inp`, their ids): each exit hands those back to the caller  |
| `g_bck_iter_live` | :4351 | `__csv_has`, `bck_fn_begin`, `bck_iter_enter`, `bck_iter_exit` | 1 while the code being compiled sits in a `~` loop over a container (`iter_containers` in g_bck is not empty): |
| `g_bck_jgb_any` | :4039 | `bck_analyze`, `bck_walk_seq` | Set once a `:` binding of a `?` / `??` took an owner (bck_join_giveback). |
| `g_bck_let_jv` | :2296 | `__assign_result_lent`, `__shadow_reset` | …and whether that right-hand side was a join or a value block: a borrow of it is a copy of the handle an arm o |
| `g_bck_let_sx_last` | :2291 | `__assign_result_lent`, `__shadow_reset` | The last `let`'s right-hand source expression (g_bck_rhs_sx), kept past its row: a join it bound is followed b |
| `g_bck_loop_defers` | :2347 | `bck_analyze` |  |
| `g_bck_match_sx` | :2971 | `bck_record`, `emit_or_chain` | The source expression of the call a `match` row matches (gen_match). |
| `g_bck_nch_any` | :53486 | `__src_mark_nc`, `bck_analyze` | …and whether any handle copy was marked one an owner cannot copy in (`nch_`, __src_mark_nc) — none: __src_drop |
| `g_bck_nrows` | :51779 | `bck_kill_stored_in_d` |  |
| `g_bck_own_params` | :193 | `__bck_answers`, `bck_defer_fn` |  |
| `g_bck_ownerless` | :2338 | `__bck_flush_ppends`, `bck_stash_store`, `bck_take_owner_stores` |  |
| `g_bck_pcap` | :51785 | `bck_alias_step` |  |
| `g_bck_pm_slot` | :27997 | `__strget_loop_warn` |  |
| `g_bck_pn` | :51784 | `bck_alias_step` |  |
| `g_bck_pr` | :51783 | `bck_alias_step` | Per id of the function analysed now: the binding it belongs to (itself unless a field path) and a path's spell |
| `g_bck_pvpass_n` | :4117 | `__vself_place`, `bck_flush_vpass`, `bck_side_lists_put`, `bck_side_lists_take` +6 |  |
| `g_bck_quiet` | :197 | `__bck_hr_drop_owner`, `bck_defer_fn` |  |
| `g_bck_rcap` | :51780 | `bck_kill_stored_in_d` |  |
| `g_bck_rcf_any` | :4050 | `__bck_rcf_link`, `bck_analyze` | Some binding of this function is an `rc_clone` of another: their Rc is one value, a family (`rcr_` the family' |
| `g_bck_rcf_busy` | :4055 | `bck_dep_add` |  |
| `g_bck_rcix` | :2949 | `__dyn_impl_tys` | g_bck_rcty by key — `name=`, `name~=`, `name+=` — each the bar list of what was noted under it (__bck_rc_note) |
| `g_bck_rcix_ok` | :2950 | `__csv_has`, `__dyn_impl_tys`, `bck_defer_fn`, `bck_fn_begin` |  |
| `g_bck_rcty` | :694 | `__csv_has`, `__dyn_impl_tys`, `bck_defer_fn`, `bck_fn_begin` | The bindings and field paths of the function being walked that hold an `Rc` handle, as `name=type` words (bck_ |
| `g_bck_rd_slot` | :27996 | `__strget_loop_warn` | Byte length of one of g_bck's statement lists (`reads`, `pmoves`) in O(1): g_bck is one flat scope that never  |
| `g_bck_rec_off` | :2361 | (init only) | >0 while the borrow checker's capture hooks must not record. Used to be spelled `g_bck_closure_depth != 0`, wh |
| `g_bck_ret_dep` | :4384 | `__ret_blk_exit_flush`, `gen_block_stmts` |  |
| `g_bck_ret_guard` | :2345 | `bck_join_giveback`, `bck_walk_seq` |  |
| `g_bck_ret_line` | :2350 | `bck_walk_seq` |  |
| `g_bck_ret_sx` | :4383 | `__ret_blk_exit_flush`, `gen_block_stmts` | The source expression of a returned view (field 8 of its `ret` row), and 1 when it is an owner returned by nam |
| `g_bck_ret_whole` | :4397 | `__ret_blk_exit_flush`, `gen_block_stmts` | The bare binding a `^` hands back whole (`^ h`, not `^ . h f`): the ret row's name field, so the walk can ask  |
| `g_bck_rhs_callee` | :47597 | `__assign_result_lent`, `__shadow_reset`, `__word_count` | The call a `let` / `assign` binds the result of (field 6 of its row): a lend the walk learns from the callee's |
| `g_bck_rhs_fview` | :4229 | `__mem_udrop_bind_flag` | A field viewer's path a binding bound from it inherits (agora #271). |
| `g_bck_rhs_lend` | :48049 | `__assign_result_lent`, `__shadow_reset`, `__word_count` | Set by a binding whose right-hand side is a call: the sources a borrow of its result has (bck_call_lend_srcs); |
| `g_bck_rhs_path` | :4227 | `__assign_result_lent`, `__shadow_reset`, `bck_note_borrow` | …and the path a binding's field-read right-hand side named (`: T n . h name` → `h.name`): what a borrow decide |
| `g_bck_rhs_sx` | :47600 | `__assign_result_lent`, `__shadow_reset`, `__word_count` | The source expression of a `let` / `assign`'s right-hand side (field 8 of a view's row, g_srcx_on): its source |
| `g_bck_rk` | :51778 | `bck_kill_stored_in_d` | …and each row's kind code (bck_kind_code). |
| `g_bck_rlen` | :51776 | `bck_kill_stored_in_d` |  |
| `g_bck_row_at` | :4013 | `bck_analyze`, `bck_walk_seq` | …and its index: whether a statement there runs on every path through the function — a row of the body's own se |
| `g_bck_row_ln` | :4009 | `bck_walk_seq` | The line of the row the walk is at, for a check that only one row's own events may make: bck_diag_self_view's. |
| `g_bck_rows` | :51775 | `bck_kill_stored_in_d` | The rows of the function being walked (bck_explode / bck_rec): copies and their lengths. |
| `g_bck_rva_any` | :53515 | `__bck_rva_add`, `__bck_rva_set`, `bck_analyze` | Whether a binding of this function's walk was bound to such an answer (`rva_`). |
| `g_bck_rvs_any` | :4054 | `bck_ret_view_check` | Some walk has answered that its function hands back a value viewing its own fields (`.rel` in g_fn_rviews): on |
| `g_bck_sc` | :4424 | `__cursor_src_of` |  |
| `g_bck_sc_cap` | :4423 | `__cursor_src_of` |  |
| `g_bck_sc_n` | :4422 | `__cursor_src_of`, `bck_walk_seq` | The blocks the walk is in, innermost last (bck_scope_push): rows [lo, hi) of each, and whether it is a loop's  |
| `g_bck_stmt_line` | :51238 | `gen_stmt` | The line of the statement being compiled, innermost — kept apart from g_stmt_line, which the diagnostics ancho |
| `g_bck_sx_gen` | :2339 | `bck_walk_seq` |  |
| `g_bck_sx_wid` | :4106 | `bck_sx_row_sweep` | While a row named by a source expression (`@sx`) is swept for one storage it is (bck_sx_row_sweep): that bindi |
| `g_bck_udrop_any` | :47570 | `bck_analyze`, `bck_kill_stored_in_d`, `bck_xlate_row1` | …and 1 once a row of the function being walked marks one (bck_xlate_row): only then does a return ask its drop |
| `g_bck_view_reads` | :47593 | `bck_flush_moves` | What a view binding's right-hand side read (bck_record_binding). |
| `g_bck_vs_any` | :4016 | `__vk_note_self`, `__vk_note_self_panic`, `bck_analyze` | Whether this walk has noted a parameter left viewing its own storage (`vscand`, __vk_note_self; agora #584). |
| `g_bck_vs_pend` | :4020 | `__csv_has`, `__vself_place`, `bck_flush_moves` | …and whether a call's `sK` rows wait, unflushed, on the statement's lists (__vself_place): a `?`'s condition,  |
| `g_bck_watch` | :2246 | `bck_analyze`, `bck_loop` | Loops being walked, nesting included; g_bck_dg follows writes only while > 0. |
| `g_bcls_memo` | :4000 | `__target_arch` | A binding class per LLVM type (bck_bind_class), and the trusted-file answer for the current source file (bck_u |
| `g_blk_depth` | :2982 | `__blk_enter` |  |
| `g_blk_froot` | :4141 | `gen_block_expr`, `mem_note_payload_part` |  |
| `g_blk_lets` | :2981 | `__blk_enter`, `__blk_tail_sx` | What the bindings declared in value-position blocks hold (h216): words `D:name=sx` (a `let` at block depth D), |
| `g_blk_scalar_let` | :2570 | `__shadow_reset`, `gen_block_expr` | The `:` binding the next block initialises is a number or a flag (gen_let_or_struct → gen_block_expr, consumed |
| `g_blk_tail_eff` | :4144 | `gen_backslash_expr`, `gen_block_expr`, `gen_try_expr` | …and the first token of its tail statement, through a tail that is itself a block (`^ { … { … ( g x ) } }`: a  |
| `g_blk_tail_lit_col` | :9794 | `gen_block_expr`, `gen_block_ret` |  |
| `g_blk_tail_lit_line` | :9793 | `emit_agg_exit`, `emit_or_chain`, `gen_block_expr`, `gen_block_ret` +1 | g_blk_tail_lit_line/col — the dangling-literal exemption's escape hatch, closed. A bare literal as a value blo |
| `g_blk_val_depth` | :2983 | `__blk_enter` |  |
| `g_body_ends` | :25028 | `body_ends_reset` | Where each brace block ends: "<text identity> <offset of a '{'>" → the offset just past its matching '}'. Ever |
| `g_borrowck` | :2198 | `__target_arch` | ── Borrow-checker state ───────────────────────────────────────── g_borrowck is 1 (ON) by default; `--no-borro |
| `g_call_cp` | :194 | `__target_arch` |  |
| `g_call_hold_set` | :671 | `mem_arg_consumption` |  |
| `g_call_jphi_set` | :2645 | `mem_arg_consumption`, `resolve_clone_hooks` | Whether the last call published a join argument's bindings (`__last_call_join_phi__`, gen_call), so the next o |
| `g_call_lend_roots` | :3983 | `gen_mem_dup`, `mem_arg_consumption` |  |
| `g_call_lroots` | :3971 | `mem_arg_consumption` | …and the same roster for the lend chain (__mem_payload_local_lend1): an argument that is itself a call that ma |
| `g_call_nest` | :186 | `__gen_call_nested` |  |
| `g_call_own_slc` | :22509 | `gen_mem_dup`, `mem_capture_hown`, `mem_propagate_call_ret_markers` | The register (`%rN`, its N) of the own bit captured right after the last call, for a slice from a callee compi |
| `g_call_proots` | :3978 | `mem_arg_consumption` | …and the roster a return of the call reads for what this function lends back: an argument that is itself a cal |
| `g_call_roots` | :3965 | `gen_mem_dup`, `mem_arg_consumption` | The call just generated, when one of its arguments was a field path (`. b items`): its arguments with that fie |
| `g_calls_total` | :2792 | `mem_arg_consumption` | …and every call completed so far, never reset: a call completed while a lent binding's own arguments were comp |
| `g_cap_outer` | :4278 | `__pderiv_cparams`, `resolve_clone_hooks` | The enclosing binding's slot of each closure body capture slot made in the function compiling now (__pderiv_pu |
| `g_cast_fresh_in` | :2368 | `__gen_cast_body`, `is_ptr_ty` |  |
| `g_cc_seen` | :91202 | `__cc_is_rc` | The edges of a value of type `ty`: each type the walk reaches is asked once — g_cc_seen, the set of those aske |
| `g_cedges` | :4312 | `__target_arch` | The summary edges such a read conditions, per function (g_rpg_me_self): `B:k:c` the elements of parameter k dr |
| `g_cg_blk_depth` | :2251 | `bck_block_enter`, `bck_block_exit`, `emit_or_chain`, `gen_block_expr` | …and the same as code generation sees it, whether or not the borrow walk records (bck_block_enter / exit): an  |
| `g_cj_depth` | :47604 | `__bck_hr_drop_owner`, `bck_analyze`, `bck_handle_cond`, `bck_handle_match` +1 | While a `?` / `??` join's arms are walked: how deep, and the borrow facts the arm walked now has changed, with |
| `g_cj_entry` | :47609 | `__bck_hr_drop_owner`, `bck_analyze`, `bck_handle_cond`, `bck_handle_match` +1 | …and the state the innermost such join started from, by address — the join's own `state`, alive while its arms |
| `g_cj_log` | :47605 | `__bck_hr_drop_owner`, `__cj_key_root`, `bck_analyze`, `bck_handle_cond` +2 |  |
| `g_clo_all_params` | :664 | `__csv_has` |  |
| `g_clo_assigned` | :2558 | `__csv_has` | The `: ~` scalars the closure being built assigns (simple_capture_analysis finds them; __gen_closure_expr publ |
| `g_clo_bind_name` | :2610 | `__csv_has`, `__shadow_reset` |  |
| `g_clo_cap_set` | :2337 | `mem_arg_consumption` |  |
| `g_clo_caps_now` | :4355 | `__csv_has` | While a closure body is compiled: what it captured (g_clo_caps_now) and the calls it hands one of them — or a  |
| `g_clo_cla_list` | :676 | `__clo_node_ty` |  |
| `g_clo_closed` | :678 | `__clo_members_attr` |  |
| `g_clo_cond_off` | :4380 | `__clo_cond_off_note`, `__csv_has` | 1 once the body has given a new value to a handle local that reaches a capture under such a condition (__clo_c |
| `g_clo_cond_ser` | :4376 | `__clo_eff_cond_k` | The conditions a closure's change of a capture waits on, numbered: `clocond##<n>` of g_pending_impl (__clo_eff |
| `g_clo_copied_val` | :2767 | `mem_retclo_own_result` | …and the last value __clo_tmp_settle copied: a copy, no lend of where it was read from (gen_ret's ret_call_cop |
| `g_clo_cur` | :662 | `__csv_has` | A call through a closure value is a call of its summary node (agora #359, #403): `name__cloN`, whose members a |
| `g_clo_deriv` | :4363 | `__csv_has`, `__sx_bind_names` | In the closure body compiling now, its handle locals read out of a capture — an element (`: ( Vec String ) e ( |
| `g_clo_deriv_c` | :4369 | `__csv_has`, `__sx_bind_names` | …and those it reaches only where a call's source expression lends out of what it names — a callee no summary i |
| `g_clo_detach` | :2599 | `__csv_has`, `mem_arg_consumption` | Set by a call compiling a closure literal as the closure a thread or a fiber runs, or by a `:` binding of one  |
| `g_clo_detach_shared` | :2593 | `__csv_has` | The detached closure's captures taken by share (__clo_detach_moves); consumed by gen_closure_expr like the mov |
| `g_clo_eff_co` | :4373 | `__csv_has`, `bck_cap_via_of` | The effects (g_closure_effects' `~cap:callee:k` words) the body has through such a read only: `<effect>#c` per |
| `g_clo_eff_set` | :2335 | `__clo_ret_member_note`, `mem_arg_consumption` |  |
| `g_clo_fld_roots` | :2580 | `__csv_has` | The outer bindings the closure being built stores a FIELD of (`= . w f …`, `= . . h w f …`): captured by refer |
| `g_clo_hold_n` | :670 | `__bar_swap_sp`, `__indirect_members` |  |
| `g_clo_inl_list` | :677 | `mem_arg_consumption` |  |
| `g_clo_lend_set` | :2333 | `mem_arg_consumption` |  |
| `g_clo_lent_val` | :2764 | `mem_retclo_own_result` | …and the last such value kept lent at its call (`<register> <owned>`), which consumers do not clear: a binding |
| `g_clo_lpnode_list` | :675 | `__clo_cs_expr` |  |
| `g_clo_node_list` | :668 | `__clo_lits_of_h` |  |
| `g_clo_node_n` | :669 | `__clo_node_mint` |  |
| `g_clo_nodes` | :667 | `__clo_cs_expr`, `__clo_node_mint`, `__clo_node_ty`, `__clo_ret_member_note` +2 |  |
| `g_clo_params` | :663 | `__csv_has` |  |
| `g_clo_pnode_list` | :674 | `__clo_cs_expr` |  |
| `g_clo_read` | :2574 | `__csv_has` |  |
| `g_clo_ret_body` | :2539 | `__csv_has` | 1 while the body of a closure that is returned right here is compiled: its env owns its captures for every cal |
| `g_clo_ret_n` | :2336 | `__clo_ret_member_note` |  |
| `g_clo_rhs_at` | :2773 | `__shadow_reset` | Where the right-hand side of the `:` binding being compiled starts (its `(`), or -1: a closure-returning call  |
| `g_clo_run_asg` | :2564 | `__csv_has`, `bck_opaque_param_run` | …and the bindings the closures its body runs give a new value by name (their `__closure_assigns`): running it  |
| `g_clo_scan_assigned` | :2571 | `__cs_outer` |  |
| `g_clo_scan_decl` | :2587 | `__clo_ctx_pop` | The names the type the scan just skipped declares: a `:` binding's, or a nested closure's parameters (__clo_sc |
| `g_clo_scan_fld_roots` | :2581 | `__cs_outer` |  |
| `g_clo_scan_read` | :2573 | `__cs_outer` | …and the outer bindings it reads (not only stores into): agora #358. |
| `g_clo_scan_structs` | :2584 | `__clo_ctx_pop`, `__cs_outer` | The closure body's own bindings of a plain struct type, as the capture scan meets them: a name after `. <one o |
| `g_clo_tk_body` | :2478 | `__csv_has` | 1 while the body of a closure whose env may mark a capture taken is compiled: a use of such a capture checks i |
| `g_clo_tmp` | :2754 | `mem_retclo_own_result` | The owned closure temporary most recently produced, as `<value> <env>` (docs/MEMORY.md §7.4): published by a c |
| `g_clo_tmp_own` | :2760 | `mem_retclo_own_result` | …and, for a temporary a callee may have LENT (mem_retclo_take_call: a closure read out of a parameter's contai |
| `g_clol_srcs` | :2797 | `__clolend_final` | …and the Vecs each lend of this function was read out of (`name k` pairs): one moved away or handed to a consu |
| `g_clolend_cur` | :2784 | `mem_arg_consumption` |  |
| `g_clolend_n` | :2326 | `mem_note_clo_bind_lend`, `mem_note_clo_lend` |  |
| `g_clolk_n` | :2783 | `mem_retclo_take_call` | A closure a callee lent (mem_retclo_take_call) stays lent in its `:` binding only while that binding is used a |
| `g_closure_consumed` | :2162 | `__clo_capture_gone`, `__csv_has`, `__sx_bind_names`, `bck_assign_alias` | Names a closure BODY consumed. bck_stash_move drops its records while inside a closure — the body's statements |
| `g_closure_defs` | :2184 | `__target_arch` |  |
| `g_closure_effects` | :4356 | `__csv_has`, `bck_cap_via_of` |  |
| `g_closure_emit_base` | :2188 | `__target_arch`, `emit_closure_globals` |  |
| `g_closure_types` | :2185 | `__target_arch` |  |
| `g_cond_depth` | :2236 | `emit_agg_exit`, `gen_loop` | Nesting depth of "we are parsing an enclosing construct's CONDITION". The arity check above fires when a `{` f |
| `g_const_pred` | :3893 | `emit_agg_exit`, `gen_mem_cyclic`, `gen_mem_drop_runs_code`, `gen_mem_rc_nested` +2 | Set by a type predicate that is a constant of the instance being generated (`( mem_cyclic [T] )`, `( mem_drop_ |
| `g_core_acks` | :252 | `eng_main` |  |
| `g_core_agg_ty` | :242 | `__mb_tmp_flag` |  |
| `g_core_agg_var` | :243 | `__mb_tmp_flag` |  |
| `g_core_callee` | :235 | `__core_bind`, `__gen_call_nested`, `mem_arg_consumption` |  |
| `g_core_callee_cap` | :263 | `__core_bind`, `__core_tab` |  |
| `g_core_callee_n` | :262 | `__core_bind`, `__core_tab` |  |
| `g_core_callee_seen` | :264 | `__core_bind` |  |
| `g_core_callees` | :261 | `__core_bind`, `__core_tab` |  |
| `g_core_code` | :210 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_code_cap` | :212 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_code_n` | :211 | `__nest_die`, `eng_main` |  |
| `g_core_depth` | :225 | `__core_bind`, `eng_main` |  |
| `g_core_ffile` | :239 | `eng_main` |  |
| `g_core_fflags` | :250 | `__core_bind`, `__nest_die`, `bck_check_raw_call`, `eng_main` |  |
| `g_core_fline` | :230 | `eng_main` |  |
| `g_core_fn_cap` | :267 | `__core_tab`, `eng_main` |  |
| `g_core_fn_n` | :266 | `__core_tab`, `eng_main` |  |
| `g_core_fname` | :228 | `eng_main` |  |
| `g_core_fns` | :265 | `__core_tab`, `eng_main` |  |
| `g_core_fret` | :229 | `eng_main` |  |
| `g_core_ftmpl` | :251 | `eng_main` |  |
| `g_core_kw_h` | :254 | `__core_bind` |  |
| `g_core_kw_slots` | :255 | `__core_bind` |  |
| `g_core_line` | :226 | `__nest_die`, `eng_main` |  |
| `g_core_live` | :209 | `eng_main` |  |
| `g_core_match_op` | :244 | `eng_main` |  |
| `g_core_match_var` | :245 | `eng_main` |  |
| `g_core_mb_elem` | :240 | `__mb_tmp_flag`, `__path_names_overlap`, `eng_main` |  |
| `g_core_nl_addr` | :241 | `eng_main`, `gen_nested_lvalue_addr` |  |
| `g_core_nparam` | :238 | `__core_bind`, `eng_main` |  |
| `g_core_on` | :208 | `__target_arch` | ── Core IR (docs/dev/PROPOSAL_CORE_IR.md §4.1, AGORA-858) ─────────── The statement language of formal/A2, bui |
| `g_core_os` | :219 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_os_cap` | :221 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_os_n` | :220 | `__core_bind`, `__nest_die`, `eng_main` |  |
| `g_core_out` | :231 | `__core_tab`, `eng_main` |  |
| `g_core_out_cap` | :233 | `__core_tab`, `eng_main` |  |
| `g_core_out_n` | :232 | `__core_tab`, `eng_main` |  |
| `g_core_pl` | :216 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_pl_cap` | :218 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_pl_n` | :217 | `__nest_die`, `eng_main` |  |
| `g_core_saved` | :227 | `eng_main` |  |
| `g_core_serial` | :236 | `eng_main` |  |
| `g_core_serial_next` | :237 | `eng_main` |  |
| `g_core_tmp_cap` | :224 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_tmp_n` | :223 | `__nest_die`, `eng_main` |  |
| `g_core_tmps` | :222 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_ty_cap` | :248 | `__core_tab`, `eng_main` |  |
| `g_core_ty_n` | :247 | `__core_tab`, `eng_main` |  |
| `g_core_ty_seen` | :249 | `eng_main` |  |
| `g_core_tys` | :246 | `__core_tab`, `eng_main` |  |
| `g_core_unlowered` | :234 | `__nest_die` |  |
| `g_core_var_cap` | :215 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_var_n` | :214 | `__nest_die`, `eng_main` |  |
| `g_core_vars` | :213 | `__core_tab`, `__nest_die`, `eng_main` |  |
| `g_core_vb` | :253 | `eng_main` |  |
| `g_core_virt_cap` | :258 | `__core_bind`, `__core_tab` |  |
| `g_core_virt_n` | :257 | `__core_bind`, `__core_tab` |  |
| `g_core_virt_seen` | :259 | `__core_bind` |  |
| `g_core_virts` | :256 | `__core_bind`, `__core_tab` |  |
| `g_coverage_link_ir` | :3060 | `__target_arch` |  |
| `g_coverage_meta_id` | :3067 | `dbg_flush` |  |
| `g_coverage_notes` | :3059 | `__target_arch` |  |
| `g_coverage_prefix` | :3058 | `__target_arch` |  |
| `g_cpu_dispatch` | :4473 | `__target_arch` | Which wider ISA the `simd` prefix dispatches to. 1 = x86-64-v3 (AVX2 + BMI2 + FMA), 0 = no dispatch, emit the  |
| `g_crypto_defer` | :4444 | `__target_arch` | Crypto-tier functions held back the same way (emit_fn_ir), and the ones among them that ask to be inlined (`in |
| `g_crypto_defer_n` | :4445 | `__emit_fn_ir`, `__target_arch`, `flush_simd_deferred` |  |
| `g_crypto_fns` | :4434 | `__target_arch` | Functions whose own IR uses a hardware crypto primitive, by IR name (emit_fn_ir) — what a deferred `simd` func |
| `g_crypto_inl` | :4446 | `__target_arch` |  |
| `g_crypto_target` | :4483 | `__target_arch` | Which hardware crypto tiers the module is built for: 1 x86-64 (AES-NI + PCLMULQDQ, and the VAES ones), 2 AArch |
| `g_cur_lent_local` | :4030 | `__mb_tmp_flag`, `gen_field_rhs` | 1 while mem_note_kept hands on a `: ~` cursor over a parameter that its store copied wherever it was the param |
| `g_cur_params` | :4289 | `resolve_clone_hooks` |  |
| `g_cur_rc` | :2880 | `resolve_clone_hooks` | …and whether a parameter of the function compiling now reaches an Rc (__fn_rc_param, set with g_cur_params): o |
| `g_cur_ret_llty` | :181 | `resolve_clone_hooks` | LLVM return type of the function whose body is currently being generated. Diagnostics-only: gen_field_store co |
| `g_dbg_blob_syms` | :3070 | `dbg_init` | module-flag id we might add later |
| `g_dbg_cu_id` | :3073 | `dbg_init` |  |
| `g_dbg_current_file_id` | :3102 | `resolve_clone_hooks` | defining path for the mono being emitted (the mono's lexer filename is the synthetic `<generic …>`). Set/resto |
| `g_dbg_current_loc` | :3076 | `__csv_has`, `__gen_stmt_level`, `dbg_synth_begin`, `dbg_synth_end` +5 | (0 outside any function) |
| `g_dbg_current_subprogram` | :3074 | `__csv_has`, `dbg_synth_begin`, `dbg_synth_end`, `resolve_clone_hooks` |  |
| `g_dbg_enabled` | :3057 | `__target_arch` | ── DWARF debug-info state ─────────────────────────────────────── All zero/empty when --g is OFF; emit helpers |
| `g_dbg_file_id` | :3072 | `dbg_init` | flushed at end-of-module by dbg_flush |
| `g_dbg_file_syms` | :3091 | `dbg_init` | uses this instead of `nurl_lex_line` for the !DISubprogram source line. Set by emit_one_instantiation so per-m |
| `g_dbg_next_id` | :3068 | `dbg_alloc_id` |  |
| `g_dbg_override_file` | :3096 | `gen_fn_decl_or_lazy`, `gen_import_decl` | every source file gets its own !DIFile and a subprogram debug-attributes to the file that DEFINES it (imports, |
| `g_dbg_override_line` | :3085 | `gen_fn_decl_or_lazy`, `gen_import_decl` | the type for every local until Phase 6 lays down per-LLVM-type DIBasicType entries indexed by `vt`. |
| `g_dbg_placeholder_ty` | :3081 | `dbg_init` | dbg_init and reused for every fn. Phase 6 will replace with per-fn signature types. |
| `g_dbg_subroutine_ty` | :3078 | `dbg_init` | emit_dbg_eol then omits `, !dbg !N`) |
| `g_dbg_type_syms` | :3136 | `dbg_init` |  |
| `g_dce` | :105326 | `__target_arch` |  |
| `g_dce_at` | :105451 | `__sp_parts` |  |
| `g_dce_defer_jrnl` | :105447 | `__sp_parts` | 1 while the reachability scan defers a journal push's thunk edge (__dce_scan, __dce_journal_edges). |
| `g_dce_end` | :105441 | `__dce_index_of`, `__sp_parts` |  |
| `g_dce_idb` | :105454 | `__sp_parts` |  |
| `g_dce_jat` | :105448 | `__dce_index_of` |  |
| `g_dce_jcap` | :105450 | `__dce_index_of` |  |
| `g_dce_jn` | :105449 | `__dce_index_of` |  |
| `g_dce_keep` | :105337 | `__target_arch` | `--keep=a,b,c` — extra DCE roots.  The pass's root set is `main` plus whatever module-scope constants name. Th |
| `g_dce_live` | :105442 | `__sp_parts` |  |
| `g_dce_map` | :105452 | `__sp_parts` |  |
| `g_dce_mod` | :105389 | `__sp_parts` | The module text, as an integer cast of a BORROWED `s`. Deliberately not a `: ~ s` global: a mutable string glo |
| `g_dce_mod_len` | :105390 | `__sp_parts` |  |
| `g_dce_qn` | :105444 | `__dce_ident_byte`, `__sp_parts` |  |
| `g_dce_queue` | :105443 | `__sp_parts` |  |
| `g_dce_start` | :105440 | `__dce_index_of`, `__sp_parts` |  |
| `g_dead_arm` | :3882 | `__ice_report`, `emit_agg_exit` | `--unsafe-report`: what the program asks to be trusted (outside the standard library), one `file:line what` pe |
| `g_dead_payload` | :70976 | `__gen_cast_body`, `__mb_tmp_flag` | Set while the payload of a None literal is generated, when that payload is a cast (gen_agg_lit): the one cast  |
| `g_defer_body_depth` | :2618 | `gen_defer` | …and how many `;` defer bodies enclose the code being generated: an owner bound there may never be bound at al |
| `g_defer_count` | :2014 | `gen_defer`, `resolve_clone_hooks` |  |
| `g_deferred_bck` | :2842 | `__target_arch` | Functions whose borrow-check walk is parked until the whole module has compiled (see borrowck_fn_end). `n` is  |
| `g_dfs_n` | :199 | `bck_defer_fn` |  |
| `g_diag_ctx` | :157 | `dyn_sig_parts`, `emit_lit_check`, `gen_import_decl`, `scan_method_signature` +2 | Diagnostic context suffix, appended to every die/warn message while non-empty. Set (and saved/restored — insta |
| `g_diag_cur_id` | :171 | `__diag_frame_id`, `gen_import_decl` |  |
| `g_diag_frame_n` | :172 | `__diag_frame_id` |  |
| `g_diag_inst_args` | :169 | `gen_import_decl` |  |
| `g_diag_notes` | :168 | `gen_import_decl` | …and what an instantiation adds after the diagnostic itself (agora #751): `g_diag_notes` holds the note of the |
| `g_diag_parent` | :170 | `gen_import_decl` |  |
| `g_diag_recover_active` | :135 | `__ice_report`, `__target_arch` |  |
| `g_did_ret` | :1958 | `__close_dead_block`, `__csv_has`, `__handle_unreachable_stmt`, `__ret_blk_exit_flush` +9 |  |
| `g_dkeep_bind` | :2309 | `__csv_has`, `__gen_stmt_level`, `resolve_clone_hooks` |  |
| `g_dkr_any` | :2310 | `mem_dkeep_rebind`, `mem_dkeep_rebind_known`, `resolve_clone_hooks` |  |
| `g_dkr_n` | :2311 | `__dkr_expand`, `__dkr_expand_closure`, `__dkr_expand_slice` |  |
| `g_dloop` | :2307 | `__csv_has`, `__dloop_close`, `__dloop_open`, `resolve_clone_hooks` |  |
| `g_dloop_exit` | :2308 | `__dexit_top`, `__dloop_close`, `__dloop_open` |  |
| `g_dmrv_memo` | :89701 | `__drop_may_read_view` | Does dropping a value of `ty` run a destructor that may read a view — a value somewhere inside it (as __holds_ |
| `g_drain_n` | :4156 | `mem_drain_deferred` | How many function exits have emitted the deferred-drop list (mem_drain_deferred) so far: a slot parked after o |
| `g_drc_memo` | :89808 | `__drop_runs_code` | May dropping a value of `ty` run code of the program's own — and so panic? A `% Drop` impl anywhere inside it; |
| `g_drop_base` | :4255 | `__target_arch` | Which parameters each safe function may drop or replace the elements of (bck_callee_drops_elems): witnessed wh |
| `g_drop_edges` | :4257 | `__target_arch` |  |
| `g_drop_gen` | :2278 | `__coherence_register`, `__vec_drop_fn`, `emit_dyn_drop_fn` |  |
| `g_drop_glue_ty` | :185 | `__csv_has`, `gen_dyn_construct`, `resolve_clone_hooks` | The LLVM type of the value a `% Drop` impl's `drop` is being compiled for (`%R`), or `` — while set, every exi |
| `g_dup_nest` | :187 | `__gen_expr_level`, `gen_mem_dup` |  |
| `g_dyn_box_reg` | :2631 | `__assign_result_lent`, `__shadow_reset`, `gen_dyn_construct` | The register number (`%r<N>`) of the `( dyn Trait v )` box that the right-hand side being bound made, or -1. T |
| `g_dyn_dtout` | :2124 | `dyn_method_slot` | dyn_method_decltrait's result rides a global too: its callers sit ABOVE its definition, so an owned return wou |
| `g_dyn_flat_out` | :2118 | `__dyn_flat_reset` | Scratch accumulators for dyn_flat_methods (a NURL fn returns one value, so the recursive supertrait walk threa |
| `g_dyn_flat_seen` | :2119 | `__dyn_flat_reset` |  |
| `g_dyn_needed` | :2115 | `__dyn_unslug` | Dynamic trait objects (`%Trait`, docs/spec.md §4.9). Space-separated set of trait names that appear as a `%Tra |
| `g_ec` | :312 | `eng_open` |  |
| `g_ec_f` | :314 | `eng_open` |  |
| `g_ec_line` | :595 | `eng_link` |  |
| `g_ec_link` | :315 | `eng_link` |  |
| `g_ec_n` | :313 | `eng_open` |  |
| `g_ec_next` | :617 | `eng_link` |  |
| `g_ee` | :394 | `__ep_init` |  |
| `g_ee_ix` | :395 | `__ep_init` |  |
| `g_ef` | :291 | `im_put` |  |
| `g_ef_code` | :292 | `im_put` |  |
| `g_ef_count` | :616 | `im_put` |  |
| `g_ef_ix` | :295 | `im_put` |  |
| `g_ef_pl` | :294 | `im_put` |  |
| `g_ef_vars` | :293 | `im_put` |  |
| `g_eff_rc_memo` | :2321 | `__eff_rc_note` |  |
| `g_el` | :419 | `eng_fn_begin` |  |
| `g_el_first` | :619 | `eng_fn_begin` |  |
| `g_el_ix` | :420 | `eng_fn_begin` |  |
| `g_el_key` | :421 | `eng_fn_begin` |  |
| `g_el_next` | :620 | `eng_fn_begin` |  |
| `g_el_shared` | :621 | `eng_fn_begin` |  |
| `g_eng_dbg` | :393 | `__target_arch` |  |
| `g_eng_on` | :290 | `__target_arch` |  |
| `g_eng_skip` | :603 | `eng_skip_why`, `eng_skip_why_s` |  |
| `g_eng_syms` | :316 | `eng_main` |  |
| `g_env_join_views` | :2527 | `__csv_has` | The captures of the closure literal being built that its env only views although it is returned right here: in |
| `g_env_moved` | :2590 | `__csv_has` | …and, for one that a thread or a fiber will run, the captures it takes over from bindings the function no long |
| `g_env_nfields` | :2535 | `gen_env_struct_type` | The number of fields of the env struct type gen_env_struct_type built last. |
| `g_env_owns_handles` | :2508 | `__csv_has` | Set around a returned closure literal's env generation (1): its String / Vec / owning-struct captures move int |
| `g_env_released` | :2542 | `__csv_has` | …and, for a closure that releases some captures itself, which (their env field is not dropped again). |
| `g_env_shared` | :2595 | `__csv_has` | …and the same set while that closure's env is built and described. |
| `g_env_tk_p` | :2532 | `__csv_has` | The field of the env being built that holds one `i1` per capture, set when the body takes that capture over (` |
| `g_ep` | :396 | `__ep_init` |  |
| `g_ep_ix` | :397 | `__ep_init` |  |
| `g_ep_tmp` | :398 | `__ep_init` |  |
| `g_epl_n` | :4343 | `emit_enum_payload_bind`, `emit_or_chain`, `resolve_clone_hooks` | Payload bindings of an enum (`__enum_pl`) in the function being compiled: while 0, nothing asks whether a valu |
| `g_err_count` | :134 | `__diag_abort`, `err_pos` |  |
| `g_et` | :317 | `__et_names` |  |
| `g_et_ix` | :319 | `__et_names` |  |
| `g_et_names` | :322 | `__et_names` |  |
| `g_et_seen` | :320 | `__et_names` |  |
| `g_et_seen_base` | :321 | `__et_ask`, `__et_asked` |  |
| `g_et_w` | :318 | `__et_names` |  |
| `g_etake_n` | :4339 | `mem_enum_take_note`, `resolve_clone_hooks` | Payload bindings of an enum the function being compiled owns (mem_enum_take_note): while 0, nothing asks wheth |
| `g_etn_Arc` | :342 | `__et_names` |  |
| `g_etn_Box` | :339 | `__et_names` |  |
| `g_etn_Channel` | :344 | `__et_names` |  |
| `g_etn_Deque` | :347 | `__et_names` |  |
| `g_etn_F` | :351 | `__et_names` |  |
| `g_etn_Locked` | :345 | `__et_names` |  |
| `g_etn_Rc` | :341 | `__et_names` |  |
| `g_etn_RwLocked` | :346 | `__et_names` |  |
| `g_etn_Set` | :348 | `__et_names` |  |
| `g_etn_Shared` | :343 | `__et_names` |  |
| `g_etn_Slice` | :340 | `__et_names` |  |
| `g_etn_String` | :337 | `__et_names` |  |
| `g_etn_T` | :350 | `__et_names` |  |
| `g_etn_Vec` | :338 | `__et_names` |  |
| `g_etn_double` | :325 | `__et_names` |  |
| `g_etn_empty` | :328 | `__et_names` |  |
| `g_etn_float` | :326 | `__et_names` |  |
| `g_etn_i1` | :324 | `__et_names` |  |
| `g_etn_i16` | :331 | `__et_names` |  |
| `g_etn_i32` | :332 | `__et_names` |  |
| `g_etn_i64` | :323 | `__et_names` |  |
| `g_etn_i8` | :329 | `__et_names` |  |
| `g_etn_i8p` | :336 | `__et_names` |  |
| `g_etn_star` | :349 | `__et_names` |  |
| `g_etn_u16` | :333 | `__et_names` |  |
| `g_etn_u32` | :334 | `__et_names` |  |
| `g_etn_u64` | :335 | `__et_names` |  |
| `g_etn_u8` | :330 | `__et_names` |  |
| `g_etn_void` | :327 | `__et_names` |  |
| `g_ext` | :106213 | `__ext_calls_back` |  |
| `g_ext_glob` | :106221 | `__ext_calls_back` |  |
| `g_ext_mlen` | :106222 | `__ext_calls_back` |  |
| `g_ext_q` | :106217 | `__ext_calls_back` |  |
| `g_ext_qn` | :106218 | `__ext_calls_back`, `__mp_query` |  |
| `g_ext_sig` | :106220 | `__ext_calls_back`, `__ext_types` |  |
| `g_f_ncap` | :409 | `eng_fn_begin` |  |
| `g_f_nv` | :411 | `eng_fn_begin` |  |
| `g_f_ret` | :410 | `eng_fn_begin` |  |
| `g_fc_callee` | :508 | `eng_apply_call` |  |
| `g_fc_cap_loans` | :476 | `eng_check_fn`, `make_closure` |  |
| `g_fc_dbefore` | :586 | `eng_check_fn` |  |
| `g_fc_defers` | :587 | `eng_check_fn` |  |
| `g_fc_dirty` | :613 | `eng_check_module` |  |
| `g_fc_dvars` | :585 | `eng_check_fn` |  |
| `g_fc_errs` | :456 | (init only) |  |
| `g_fc_exits` | :589 | `eng_check_fn` |  |
| `g_fc_final` | :455 | `eng_check_fn`, `stmt_foreach`, `stmt_loop` |  |
| `g_fc_first` | :591 | (init only) |  |
| `g_fc_first_stmt` | :596 | `eng_check_fn` |  |
| `g_fc_line` | :458 | `eng_check_fn`, `eng_stmt` |  |
| `g_fc_loopmemo` | :607 | `eng_check_fn` |  |
| `g_fc_loops` | :590 | `eng_check_fn` |  |
| `g_fc_moved_own` | :482 | `eng_check_fn`, `move_out` |  |
| `g_fc_moved_vid` | :481 | `closure_takes_over`, `eng_check_fn`, `eng_reroot`, `eng_rvalue` +3 |  |
| `g_fc_order` | :605 | `eng_select` |  |
| `g_fc_reading` | :609 | `eng_check_module` |  |
| `g_fc_ret_changed` | :479 | `eng_check_fn`, `eng_effect`, `stmt_ret` |  |
| `g_fc_ret_fresh` | :480 | `eng_check_fn`, `stmt_ret` |  |
| `g_fc_ret_watch` | :478 | `eng_check_fn`, `stmt_ret` |  |
| `g_fc_rets` | :588 | `eng_check_fn` |  |
| `g_fc_tails` | :483 | `eng_fn_begin` |  |
| `g_fc_trusted` | :581 | `eng_select` |  |
| `g_fc_unsup` | :457 | `eng_check_fn`, `eng_lowerable`, `eng_unsup`, `eng_unsup_s` |  |
| `g_fc_walked` | :582 | `eng_select` |  |
| `g_fc_walking` | :477 | `eng_check_fn`, `stmt_foreach` |  |
| `g_fc_weak` | :606 | `eng_apply_call`, `eng_check_fn`, `run_closures` |  |
| `g_fe` | :614 | `eng_check_module` |  |
| `g_fe_cur` | :615 | `eng_check_module` |  |
| `g_ff_any` | :2286 | `mem_ff_slot`, `resolve_clone_hooks` |  |
| `g_ff_gen` | :2285 | `resolve_clone_hooks` |  |
| `g_ff_mark` | :2312 | `mem_emit_gated_drop`, `mem_udrop_take_old` |  |
| `g_ffi_host_imports` | :2205 | `__target_arch` | g_ffi_host_imports is 1 when `--ffi-host-imports` is passed: external `&`-FFI libraries are then satisfied by  |
| `g_ffx_n` | :2313 | `__ffx_expand` |  |
| `g_fn_arcseen` | :2951 | `mem_arg_consumption`, `resolve_clone_hooks` |  |
| `g_fn_cloparams` | :2699 | `__target_arch` | Per-callee CLOSURE-ARGUMENT map: the argument indices a call handed a closure at (gen_call), for __bck_param_c |
| `g_fn_compiled` | :2866 | `__target_arch` | Names of functions whose body has been compiled — the "is the inline summary trustworthy for this callee?" tes |
| `g_fn_drops` | :4283 | `__target_arch` |  |
| `g_fn_eparams` | :2695 | `__target_arch` | `g_fn_eparams[fname]`: the parameters that are views of a container — a Slice, a struct of views, not an `s` — |
| `g_fn_escapes` | :2718 | `__target_arch` | Per-function escaping-parameter map. `g_fn_escapes[fname]` is the space-separated list of 0-based indices of p |
| `g_fn_handkeeps` | :2680 | `__target_arch` | The kept parameters whose value this function keeps ONLY in a struct the program manages by hand through a poi |
| `g_fn_hparams` | :48235 | `resolve_clone_hooks` |  |
| `g_fn_ifreallocs` | :4267 | `__target_arch` |  |
| `g_fn_inout` | :2393 | `__target_arch` | Per-function inout-parameter map. `g_fn_inout[fname]` is the space-separated list of 0-based indices of `inout |
| `g_fn_invoke_only` | :2745 | `__target_arch` | Per-function *invoke-only* parameter map (closure-env reclamation, docs/MEMORY.md §7.4). `g_fn_invoke_only[fna |
| `g_fn_io_names` | :2635 | `llvm_call_fn` | The names of the `inout` parameters of the function being compiled (and of a closure body in it): gen_call's h |
| `g_fn_ioh_names` | :2638 | `__auto_str_ctx`, `llvm_call_fn` | …and those of a handle type, which no summary makes a `sink` (__note_ioh_params, agora #776). |
| `g_fn_ireallocs` | :4260 | `__target_arch` |  |
| `g_fn_keeps` | :2411 | `__target_arch` | Per-function KEPT-parameter map (docs/MEMORY.md §7.6): indices of parameters whose value the body stores somew |
| `g_fn_link_exports` | :2063 | `__target_arch` |  |
| `g_fn_link_sources` | :2062 | `__target_arch` | Source identities stay unmangled in semantic tables and diagnostics. Only their LLVM linkage names enter the p |
| `g_fn_mutates` | :2922 | `__target_arch` | Per-function container-mutation summary (docs/MEMORY.md §2.5). `g_fn_mutates[fname]` lists the 0-based paramet |
| `g_fn_mutates_witness` | :2923 | `__csv_has`, `mem_arg_consumption`, `resolve_clone_hooks` |  |
| `g_fn_noreturn` | :3036 | `__target_arch` | Noreturn registry. `g_fn_noreturn[fname]` is `1` when a call to fname never returns to its caller. Seeded with |
| `g_fn_pos_syms` | :2058 | `__target_arch` |  |
| `g_fn_rcp` | :2448 | `__target_arch` | g_fn_rcp[f]: the Rc types whose payload the value f hands back may be read through (`:` and words, `%Rc__T` or |
| `g_fn_reallocs` | :3007 | `__target_arch` | `g_fn_reallocs[fname]`: the parameters whose BUFFER the function may move or release (a reallocation, a free)  |
| `g_fn_reallocs_witness` | :3008 | `__csv_has`, `resolve_clone_hooks` |  |
| `g_fn_replaces` | :3018 | `__target_arch` | `g_fn_replaces[fname]`: the `inout` parameters an owned field of which (or the whole value) the function may r |
| `g_fn_replaces_witness` | :3019 | `__csv_has`, `emit_rawdrop_thunk`, `resolve_clone_hooks` |  |
| `g_fn_ret_alias` | :2913 | `__target_arch` | Per-function returned-HANDLE map — the ownership dual of g_fn_ret_param, and deliberately a separate map rathe |
| `g_fn_ret_count` | :3041 | `__ret_blk_exit_flush`, `resolve_clone_hooks` | Count of `^` statements seen while compiling the current function body (closure bodies included — that over-co |
| `g_fn_ret_param` | :2899 | `__target_arch` | Per-function returned-parameter map. `g_fn_ret_param[fname]` is the space-separated list of 0-based indices of |
| `g_fn_ret_view` | :2731 | `__target_arch` | Per-function RETURNS-A-VIEW map. `g_fn_ret_view[fname]` is set when the body builds an aggregate one of whose  |
| `g_fn_rviews` | :2440 | `__target_arch` | Per-function RESULT answer (A2's `rholds`, agora #422): `:` then the parameter indices whose own storage the v |
| `g_fn_safe` | :4287 | `__target_arch` |  |
| `g_fn_safe_list` | :4288 | `__clo_members_attr`, `__csv_has`, `__drop_base_add`, `resolve_clone_hooks` |  |
| `g_fn_semi` | :2306 | `resolve_clone_hooks` | A `;` defer inside a loop body (agora #655): see __dloop_open. |
| `g_fn_sink` | :2401 | `__target_arch` | Per-function sink-parameter map: space-separated parameter indices from explicit signatures and consuming call |
| `g_fn_slice_decls` | :2012 | `mem_slice_decl_add`, `resolve_clone_hooks` | Cheap per-function gate for the Phase 2D slice machinery: most functions declare no owned slices at all, and t |
| `g_fn_stores` | :2673 | `__target_arch` | The kept parameters whose value ends up somewhere the compiler drops — a literal, a local struct, a container  |
| `g_fn_strp` | :189 | `__auto_str_ctx`, `__own_sink_str_params` |  |
| `g_fn_tdrops` | :4286 | `__fn_sync_params`, `__thr_unsync_drop` | …as the thread rules read them: the drops made with no synchronisation (__drops_close, built when one first as |
| `g_fn_unverified` | :2703 | `__target_arch` | Retention through an unverified foreign or indirect call. Lifetime-only facts; kept separate from diagnostic e |
| `g_fn_vcopies` | :2689 | `__target_arch` | The parameters whose elements' views a function copies into another container it was handed, or into its resul |
| `g_fn_vholds` | :2466 | `__target_arch` | Per-function HOLDER map of the values it keeps (agora #414): `:` then `h>k` pairs, parameter h may be left hol |
| `g_fn_vkeeps` | :2425 | `__target_arch` | Per-function BUFFER-VIEW map (agora #301): indices of the parameters whose own storage — a String's buffer, a  |
| `g_fn_vkpend` | :2426 | `__target_arch` |  |
| `g_fold_cap` | :105764 | `__fold_kind` |  |
| `g_fold_dscap` | :105793 | `__fold_kind` |  |
| `g_fold_dstores` | :105791 | `__fold_kind` |  |
| `g_fold_end` | :105800 | `__ext_calls_back`, `__fold_reg` |  |
| `g_fold_eolcap` | :105812 | `__fold_kind` |  |
| `g_fold_eols` | :105810 | `__fold_kind` |  |
| `g_fold_fcap` | :105770 | `__fold_jrnl_tok` |  |
| `g_fold_flags` | :105755 | `__sp_parts` | ── Late flag folding ────────────────────────────────────────────  Whether a callee takes a parameter over (si |
| `g_fold_flist` | :105768 | `__fold_jrnl_tok` |  |
| `g_fold_fn_end` | :105801 | `__fold_arg_false` |  |
| `g_fold_fsave` | :105797 | `__fold_flag_line` |  |
| `g_fold_fscap` | :105798 | `__fold_flag_line` |  |
| `g_fold_grown` | :105799 | `__fold_kind` |  |
| `g_fold_jcap` | :105776 | `__fold_kind` |  |
| `g_fold_jlist` | :105774 | `__fold_kind` | The flags a journal registration reads (nurl_journal_push_drop2), this round: a call made while one is registe |
| `g_fold_k` | :105802 | `__fold_operand` |  |
| `g_fold_ldcap` | :105796 | `__fold_kind` |  |
| `g_fold_loads` | :105794 | `__fold_kind` |  |
| `g_fold_map` | :105763 | `__fold_kind` | Six words per register: 0 kind (0 none, 1 i1 constant, 2 text alias), 1-2 the constant or the alias's byte ran |
| `g_fold_nds` | :105792 | `__fold_arg_false`, `__fold_kind` |  |
| `g_fold_neol` | :105811 | `__fold_arg_false`, `__fold_kind` |  |
| `g_fold_nf` | :105769 | `__fold_arg_false`, `__fold_jrnl_tok`, `__fold_kind` |  |
| `g_fold_nj` | :105775 | `__fold_arg_false`, `__fold_kind` |  |
| `g_fold_nld` | :105795 | `__fold_arg_false`, `__fold_kind` |  |
| `g_fold_nrl` | :105789 | `__fold_arg_false`, `__fold_kind` |  |
| `g_fold_nt` | :105766 | `__fold_kind` |  |
| `g_fold_pc` | :105807 | `__dce_index_of`, `__fold_arg_false` |  |
| `g_fold_pc0` | :105806 | `__dce_index_of` |  |
| `g_fold_rlcap` | :105790 | `__fold_kind` |  |
| `g_fold_rlines` | :105788 | `__fold_kind` |  |
| `g_fold_tcap` | :105767 | `__fold_kind` |  |
| `g_fold_touched` | :105765 | `__fold_kind` |  |
| `g_fold_wa` | :105813 | `__fold_flush`, `__fold_write` |  |
| `g_fold_wb` | :105814 | `__fold_flush`, `__fold_write` |  |
| `g_fold_x` | :105803 | `__fold_jrnl_regs`, `__fold_last_arg`, `__fold_operand`, `__fold_store_flag` |  |
| `g_fold_y` | :105804 | `__fold_last_arg`, `__fold_operand`, `__fold_store_flag` |  |
| `g_fp` | :407 | `eng_fn_begin` |  |
| `g_fp_mode` | :408 | `eng_fn_begin` |  |
| `g_frozen_impls` | :2931 | `__coherence_register` | Whether the program declares any `% Frozen` impl (gen_call asks only then). |
| `g_frz_memo` | :2933 | `__lty_frozen` | __ty_lend_frozen's answers, per lowered type (`0` / `1` / `2`). |
| `g_frzp_any` | :2929 | `__arcp_note` | Whether any callee takes a `% Frozen` handle (`frzp##`): what it lends is frozen as an Arc's payload is, and r |
| `g_fs_late_n` | :70638 | `__fs_late_add`, `__fs_late_emit` | A field's old value whose drop runs code of the program's own leaves the field before that code runs, as a bin |
| `g_func_count` | :2187 | `__csv_has`, `__gen_call_kwargs_body`, `__target_arch`, `store_closure_func` |  |
| `g_fv_pidx` | :406 | `eng_fn_begin` |  |
| `g_fv_ty` | :405 | `eng_fn_begin` |  |
| `g_fx` | :459 | `eng_check_fn` |  |
| `g_fx_agg` | :461 | `eng_check_fn` |  |
| `g_fx_lent` | :463 | `eng_check_fn` |  |
| `g_fx_litp` | :462 | `eng_check_fn` |  |
| `g_fx_nocopy` | :460 | `eng_check_fn` |  |
| `g_generic_struct_syms` | :2016 | `__target_arch` |  |
| `g_generic_syms` | :2015 | `__target_arch` |  |
| `g_hd_vis` | :22503 | `__hown_dyn` | (The functions the last walk met, for __hown_dyn's memo.) |
| `g_hfb_memo` | :53518 | `__bck_answers` | __held_fallback's answers while the parked walks run (every summary is final then); 0 otherwise. |
| `g_hmemo_depth` | :89386 | `__is_owned_struct_ty` |  |
| `g_hmemo_log` | :89385 | `__is_owned_struct_ty` | ── Coinductive memo for the handle predicates ─────────────────────  `__is_owned_struct_ty` and `__clone_suppo |
| `g_hrp_n` | :672 | `__hroute_park` |  |
| `g_hud_memo` | :89810 | `__seen_parent_of` | …and __holds_user_drop's, the same way. |
| `g_hud_pmemo` | :2277 | `__seen_parent_of` | __holds_user_drop's answers across questions, `<generation>:<0\|1>` per type: a `% Drop` impl registered later, |
| `g_ic_cap` | :81620 | `__resolve_handkeep_list` |  |
| `g_ic_dirty` | :81621 | `__resolve_handkeep_list` |  |
| `g_ic_hi` | :81624 | `__resolve_handkeep_list` |  |
| `g_ic_idx` | :81622 | `__resolve_handkeep_list` |  |
| `g_ic_lo` | :81623 | `__resolve_handkeep_list` |  |
| `g_ic_n` | :81619 | `__resolve_handkeep_list` |  |
| `g_ic_next` | :81625 | `__resolve_handkeep_list` |  |
| `g_ic_off` | :81618 | `__resolve_handkeep_list` |  |
| `g_ic_rec` | :81617 | `__resolve_handkeep_list` | ── The implication rounds, semi-naively (agora #305) ────────────  The resolvers run their rounds until nothin |
| `g_ifr_edges` | :4266 | `__target_arch` | …those of the edges whose handle may be a field path of the parameter — not an element read out of a container |
| `g_impl_name_syms` | :2021 | `__target_arch` |  |
| `g_impl_pos_syms` | :2087 | `__target_arch` | `@ fname` scan registration. Two files are free to each have a private `__get`-style helper IN THEIR OWN HEADS |
| `g_impl_ret_syms` | :2020 | `__target_arch` |  |
| `g_impl_trait_syms` | :2022 | `__target_arch` |  |
| `g_impl_unsafe` | :3923 | `__coherence_register`, `scan_fn_sigs` | 1 while scan_impl_decl reads an impl written `unsafe % Trait Type { }`. |
| `g_import_aliases` | :76221 | `__import_alias_check` | ── Closure expression \ param* → type { ... } ─────────────────── Generates a function pointer value that capt |
| `g_import_roots` | :3066 | `__alias_orig_name` | The directories an import may resolve into (--import-root=DIR, repeatable, else NURL_IMPORT_ROOTS=DIR:DIR…), c |
| `g_in_cap` | :23812 | `__sym_hash_n` |  |
| `g_in_chunk` | :23814 | `__sym_hash_n` |  |
| `g_in_end` | :23816 | `__sym_hash_n` |  |
| `g_in_match_arm` | :2002 | `emit_or_chain` | Non-zero while parsing a `??` match-arm body. The XOR-confusion warning in gen_ret keys off "a non-terminator  |
| `g_in_n` | :23813 | `__sym_hash_n` |  |
| `g_in_pos` | :23815 | `__sym_hash_n` |  |
| `g_in_tab` | :23811 | `__sym_hash_n` | ── Interned strings ────────────────────────────────────────────── Every key and every plain value the symbol  |
| `g_in_unsafe` | :3926 | `resolve_clone_hooks` | 1 while the body of an `unsafe` function (or of a closure inside one) is being compiled. |
| `g_init_globals` | :1985 | `const_eval_int` | Globals set once at program start (`: ( Locked T ) g ( make )`), as `<name> <function> <type>;` triples: the e |
| `g_init_terminated` | :4530 | `__shadow_reset` | g_init_terminated — 1 while a `:` binding's own INITIALISER terminated the block and the statement's remaining |
| `g_inl_wrap` | :4450 | `__target_arch` | Inline-wanting functions that use no crypto primitive themselves, by emission order (emit_fn_ir): the candidat |
| `g_inl_wrap_n` | :4451 | `__emit_fn_ir`, `__target_arch`, `flush_simd_deferred` |  |
| `g_input_key` | :105675 | `__target_arch` |  |
| `g_input_source` | :105674 | `__target_arch` | Borrowed aliases to main's live source/key bindings when --stdin supplies an overlay. Every source read (inclu |
| `g_inst_done` | :98395 | `flush_deferred_instantiations` | flush_deferred_instantiations: emit all queued generic instantiations. Re-reads count each iteration so transi |
| `g_inst_tmpl` | :3961 | `gen_import_decl` | The template a generic instance is being compiled from (its unsafe-ness). |
| `g_irealloc_any` | :4282 | `__words_cond` |  |
| `g_irealloc_edges` | :4259 | `__target_arch` | g_fn_ireallocs and its call edges (resolve_irealloc_summaries). |
| `g_irealloc_fns` | :4281 | `__words_cond` | …and the functions that have such an edge, and whether any function has such a summary (the walks ask g_fn_ire |
| `g_iter_byname` | :37494 | `__iter_byname_note` | Where the by-name rule refused a change of a container a `~` loop iterates (`<file>:<line>` → `1`), or parked  |
| `g_iter_cur_pend` | :37499 | `__iter_emit_or_hold`, `resolve_pending_iter_mut` | The walk's messages held back so: under `*recs` one a line, in order — `<file>:<line>` of the change, the line |
| `g_iter_refused` | :37486 | `__iter_refused_note` | Where a closure that changes a container a `~` loop iterates was refused, run inside that loop (__iter_closure |
| `g_iter_resolved` | :37502 | `resolve_pending_iter_mut` | 1 once resolve_pending_iter_mut has run: the by-name answers are known, and a walk parked until the summaries  |
| `g_join_deep` | :4220 | `__assign_result_lent`, `__ret_blk_exit_flush`, `emit_agg_exit`, `emit_or_chain` | …and whether one of those arms lent what it bound there (a view, a field of one): the assignment copies the jo |
| `g_join_droot` | :4222 | `emit_agg_exit`, `emit_or_chain` | (…and the binding that arm read: what a refusal names.) |
| `g_join_flends` | :4140 | `__ret_blk_exit_flush`, `emit_agg_exit`, `emit_or_chain` | Whether a lending arm of the last `?` / `??` lent a field of this frame's own value (`? c . p s ( mk )`, p a l |
| `g_join_lent` | :4217 | `__vb_tail_takes`, `emit_agg_exit`, `emit_or_chain` | Did an arm of the join that last published its ownership (`__last_join_own__`) lend what it yields — the const |
| `g_join_pkept` | :4347 | `__arm_flends`, `__mem_udrop_bind_flag`, `__ret_blk_exit_flush`, `resolve_clone_hooks` | 1 once an arm of the join being compiled yielded such a payload (__arm_flends): the `:` binding the join's val |
| `g_join_rdepth` | :4177 | `__assign_result_lent`, `__blk_bind_tt`, `__ret_blk_exit_flush`, `emit_agg_exit` +1 | The scope depth of the binding the next `?` / `??` hands its value to, when that binding is assigned (`= t ? … |
| `g_jpb_depth0` | :4192 | `__blk_bind_tt` |  |
| `g_jpb_last` | :4195 | `__shadow_reset` | What the `:` binding being made took over from its join, while it is registered: those owners are its own now, |
| `g_jpb_list` | :4191 | `__blk_bind_tt`, `__jpb_jdepth`, `__shadow_reset` |  |
| `g_jpb_on` | :4190 | `__blk_bind_tt`, `__shadow_reset` | A `:` binding of a `?` / `??` (docs/MEMORY.md §2.2): the owner an arm selects moves into the binding on that p |
| `g_last_alloc_reg` | :2367 | `__assign_result_lent`, `__csv_has`, `__shadow_reset`, `is_ptr_ty` +2 | The register a fresh allocation's address is in (nurl_alloc, nurl_zalloc, malloc, calloc, alloc, zalloc — thro |
| `g_last_alloc_size` | :2373 | `__csv_has`, `is_ptr_ty`, `mem_arg_consumption`, `resolve_clone_hooks` | …and its byte count, when that memory is not zeroed (nurl_alloc, nurl_malloc, malloc): a cast of it to a struc |
| `g_last_cast_direct` | :1972 | `__gen_cast_body` | 1 when the last cast cast a binding (gen_cast; gen_agg_lit reads it) |
| `g_last_closure_cs` | :2152 | `__csv_has` |  |
| `g_last_closure_fn` | :666 | `__csv_has` |  |
| `g_last_closure_nonsend` | :2135 | `__csv_has` | record per impl block, verified after scan_fn_sigs once every impl across the program (incl. imports) is regis |
| `g_last_type_ptr` | :23667 | `nurl_str_cmp` |  |
| `g_layouts_final` | :2281 | `nurlc_print_help` | 1 once every named layout is read (read_type_layouts): an answer about a type's fields may be kept from then o |
| `g_lazy` | :85597 | `nurlc_print_help` |  |
| `g_lazy_edges` | :85617 | `lazy_reach`, `nurlc_print_help` | The program's reference graph, collected while scan_fn_sigs walks every file (0 when lazy compilation cannot r |
| `g_lazy_force` | :85599 | `gen_fn_decl_or_lazy`, `gen_import_decl`, `verify_super_obligations` |  |
| `g_lazy_live` | :85619 | `lazy_reach` | The functions lazy_reach found reachable from the roots: compiled in place. |
| `g_lazy_queue` | :85601 | `gen_fn_decl_or_lazy` |  |
| `g_lazy_root` | :85598 | `nurlc_print_help` |  |
| `g_lazy_scan` | :85600 | `gen_fn_decl_or_lazy` |  |
| `g_lazy_trace` | :85602 | `nurlc_print_help` |  |
| `g_lendcopy_any` | :48053 | `__lendcopy_note` | 1 once a `:` has bound a struct copy of a lend in this module (__lendcopy_note, agora #798): only then do `:`, |
| `g_let_self_src` | :4231 | `__shadow_reset` | `: T s s`: the slot of the binding the new one shadows (agora #792). |
| `g_lib_kind_memo` | :4256 | `__target_arch` |  |
| `g_lint` | :4515 | `__target_arch` | Unused-symbol lint (opt-in via `--lint`). Default OFF so ordinary builds — and the compiler's own bootstrap, w |
| `g_lint_fpend` | :4521 | `lint_init` | g_lint_fpend — the redundant-free lint's pending release calls (see lint_free_cand). |
| `g_lint_gen` | :4522 | `lint_fn_begin` |  |
| `g_lint_reads` | :4518 | `lint_init` |  |
| `g_lint_recording` | :4537 | `nurlc_print_help` | 1 only during the main parse_program pass. Cleared before flush_deferred_instantiations so synthetic generic m |
| `g_lint_syms` | :4516 | `lint_init` |  |
| `g_lint_used` | :4517 | `lint_init` |  |
| `g_live_lexers` | :24052 | `__lx_is_space` |  |
| `g_live_symtables` | :24051 | `__sym_hash_n` |  |
| `g_lm_calls` | :2851 | `__mb_tmp_flag`, `mem_arg_consumption` | While an aggregate literal is built (g_lm_depth > 0): every bare identifier a call in it hands to its callee,  |
| `g_lm_depth` | :2853 | `__mb_tmp_flag` |  |
| `g_lm_inner` | :2852 | `__mb_tmp_flag` |  |
| `g_lm_pend` | :2854 | `__lm_moved_names` |  |
| `g_lm_pend_n` | :2860 | `__lm_moved_names` |  |
| `g_loop_body_open` | :673 | `gen_block_stmts`, `gen_foreach`, `gen_loop` |  |
| `g_loop_break_used` | :3052 | `__target_arch` | `g_loop_break_used[serial]` is `1` when a `break` targeting the loop numbered `serial` (g_loop_serial, which n |
| `g_loop_nest` | :2304 | `gen_foreach`, `gen_loop` |  |
| `g_loop_serial` | :2600 | `gen_foreach`, `gen_loop` |  |
| `g_lsrc_imemo` | :3996 | `__bck_answers` | …and as bits per callee (mem_fn_lends_arg). |
| `g_lsrc_memo` | :3994 | `__bck_answers` | What each callee lends (mem_fn_lend_sources), once every summary is final: the deferred walks' memo, 0 outside |
| `g_lview_n` | :4152 | `mem_note_lview`, `resolve_clone_hooks` | How many bindings of the function being compiled view a value held elsewhere (`__lview`, mem_note_lview): none |
| `g_m_heldcol` | :2957 | `emit_or_chain` |  |
| `g_m_heldtys` | :2956 | `emit_or_chain`, `mem_arg_consumption` | The holders (lowered types, each ended by `\n`) that the calls of the `??` scrutinee being generated took as a |
| `g_match_ser` | :2303 | `emit_or_chain` |  |
| `g_max_nesting` | :143 | `__target_arch` | The limit, 0 for none: --max-nesting / NURL_MAX_NESTING, else 1000 (nurlc_print_help says so too). |
| `g_max_nesting_set` | :146 | `__target_arch` | Who set g_max_nesting: 0 the default or the variable, 1 a flag, 2 --max-nesting-fixed (then nothing changes it |
| `g_maybe_moved` | :2216 | `__target_arch` |  |
| `g_member_obj` | :2315 | `__mb_tmp_flag`, `__vb_gone_check`, `mem_arg_consumption` |  |
| `g_member_path` | :4131 | `__mb_tmp_flag` |  |
| `g_member_path_on` | :4130 | `__assign_result_lent`, `__mb_tmp_flag`, `__ret_blk_exit_flush`, `__shadow_reset` +6 | The field path the last member read named (`. . s a h` → `s.a.h`; an element read through a pointer is the poi |
| `g_member_path_raw` | :4134 | `__mb_tmp_flag` | …and 1 when that path stopped at a raw pointer (gen_member): the fields of an element read through it are the  |
| `g_mono_tparam_tys` | :3119 | `gen_import_decl` | Space-separated list of the concrete type-arguments substituted for a generic function's type parameters in th |
| `g_most_n` | :4212 | `__most_init`, `resolve_clone_hooks` | The `: ~` bindings of the function being compiled whose `__most` is kept. |
| `g_mp` | :105876 | `__ext_calls_back`, `__mp_query` | ── Journal elision ───────────────────────────────────────────────── A temporary registered with the panic jou |
| `g_mp_cclone` | :105888 | `__mp_query` |  |
| `g_mp_cdrop` | :105887 | `__mp_query` | The runtime's closure-environment entries run a method of the env they are handed — its drop, its copy, its cr |
| `g_mp_csend` | :105889 | `__mp_query` |  |
| `g_mp_rt` | :105877 | `__ext_calls_back`, `__mp_query` |  |
| `g_mplx` | :4318 | `emit_or_chain`, `resolve_clone_hooks` | The matches over a call whose lend no name carries, of the function compiling now: `ser=sx` words, its source  |
| `g_msealed` | :2331 | `__mb_tmp_flag` | The last field read (gen_member) was out of a sealed representation, at any depth of its chain, or out of a bi |
| `g_msealed_ty` | :2332 | `__mb_tmp_flag` |  |
| `g_nc_flag_caps` | :2548 | `__csv_has` | The captures of the closure being built that cannot be copied, owned by a binding of the enclosing frame, in a |
| `g_nc_own_caps` | :2553 | `__csv_has` | …and those of a closure returned from the frame: the env owns them under a flag of its own, which the body cle |
| `g_ncl_n` | :4148 | `__nc_bind_lend_note`, `resolve_clone_hooks` | How many bindings of the function being compiled hold a value that cannot be copied which a call may lend (`__ |
| `g_nest_abort` | :149 | `__nest_die` | 1 once a program passed the nesting limit: every parse_program walk stops at the declaration it is in, without |
| `g_nest_depth` | :140 | `__ice_report`, `__nest_enter`, `gen_expr`, `gen_stmt` +1 | The nesting limit (see `── Nesting limit` above gen_expr): the gen_expr / gen_stmt / parse_type levels open no |
| `g_nl_buf` | :83407 | `__tb_body` | N newlines — the re-lex padding that maps a template buffer's line 1 onto the template's real source line (see |
| `g_noaddr_depth` | :2282 | `__ty_no_address_enum` |  |
| `g_noaddr_stamp` | :2283 | `__ty_no_address_enum` |  |
| `g_noaddr_vis` | :2284 | `__ty_no_address_enum` |  |
| `g_nroots_memo` | :4315 | `__clo_cond_live`, `resolve_cond_edges` | (The names each source expression lends out of, asked by resolve_cond_edges: `:` and its words, per sx.) |
| `g_open_bind_col` | :2609 | `__shadow_reset` |  |
| `g_open_bind_line` | :2608 | `__shadow_reset` |  |
| `g_open_bind_name` | :2607 | `__shadow_reset` | The binding whose initialiser is being generated (name, and where its `:` statement starts), "" outside one. A |
| `g_origin_functions` | :80310 | `__target_arch` |  |
| `g_origin_named` | :80308 | `bck_record_inferred_escape`, `origin_expr` |  |
| `g_origin_nodes` | :80307 | `bck_record_inferred_escape`, `origin_expr` | Return-escape inference (docs/MEMORY.md §2.8): record that the enclosing function may RETURN this bare-identif |
| `g_origin_returns` | :80311 | `__target_arch` |  |
| `g_origin_work` | :80309 | `bck_record_inferred_escape`, `origin_expr` |  |
| `g_ost` | :4208 | `__target_arch` | What the function being compiled hands back when it answers "owned" (agora #594, mem_ost_note) — per function, |
| `g_outer_params` | :665 | `resolve_clone_hooks` |  |
| `g_owned_globals` | :1980 | `const_eval_int` | Names of the mutable string globals that own their buffer (each has a compiler-emitted `<name>__nurlown` flag) |
| `g_part_n` | :4160 | `__mem_udrop_bind_flag`, `resolve_clone_hooks` | How many bindings of the function being compiled are cursors over part of a value (`__alias_part`) or may hold |
| `g_pay_full` | :48965 | `__ty_kids` |  |
| `g_pay_gen` | :48967 | `__ty_kids` |  |
| `g_pay_libopq` | :48963 | `__ty_kids` |  |
| `g_pay_memo` | :48968 | `__ty_kids` |  |
| `g_pay_nodes` | :48961 | `__ty_kids` | ── What sits in an Arc's payload (agora #646) ─────────────────────  A `??` payload lent by a call over a valu |
| `g_pay_opq` | :48962 | `__ty_kids` |  |
| `g_pay_seen` | :48966 | `__ty_kids` |  |
| `g_pay_wv` | :48964 | `__ty_kids` |  |
| `g_pd_ek` | :4275 | `__sx_elem_head`, `resolve_clone_hooks` |  |
| `g_pd_put` | :2876 | `__pderiv_cparams`, `__pderiv_params`, `resolve_clone_hooks` | …and the slots of the locals parameters were PUT into that way, or by a literal (`: H x @ H { h 1 }`): the who |
| `g_pderiv` | :4294 | `__drop_note_sx`, `__pderiv_cparams`, `__pderiv_params`, `resolve_clone_hooks` | The handle bindings of the safe function compiling now that were read out of a parameter — an element (`( vec_ |
| `g_pderiv_cn` | :4304 | `__pderiv_cnote`, `resolve_clone_hooks` | …and those read out of one only where a source expression lends out of what it names — a lend no name carries  |
| `g_pending_escape` | :2814 | `__target_arch` | Deferred interprocedural-escape checks (docs/MEMORY.md §3 forward / generic boundary). A stack reference passe |
| `g_pending_impl` | :2836 | `__target_arch` | Deferred summary IMPLICATIONS (docs/MEMORY.md §2.7 / §2.8). A summary is inferred as each body compiles, so a  |
| `g_pending_inline` | :3829 | `parse_toplevel_decl`, `resolve_clone_hooks`, `scan_fn_sigs` | g_pending_inline is the `inline` prefix's counterpart to g_pending_simd: set when the parser consumes a TT_INL |
| `g_pending_pub` | :3818 | `parse_toplevel_decl`, `scan_fn_sigs`, `vis_take_pending_pub` | Visibility (grammar v2.0). Tracks the source-file of every @-defined function and per-file strict-mode opt-in. |
| `g_pending_raw` | :3838 | `scan_fn_sigs` |  |
| `g_pending_rawrep` | :3842 | `gen_struct_decl`, `parse_toplevel_decl` | `raw : Name { … }`: the struct's fields carry an invariant its API keeps (a device address that must stay insi |
| `g_pending_simd` | :3824 | `parse_toplevel_decl`, `resolve_clone_hooks`, `scan_fn_sigs` | g_pending_simd is the `simd` prefix's counterpart to g_pending_pub: set when the parser consumes a TT_SIMD ahe |
| `g_pending_unsafe` | :3831 | `gen_ffi_decl`, `parse_toplevel_decl`, `resolve_clone_hooks`, `scan_fn_sigs` | The `unsafe` prefix parsed ahead of the next declaration. |
| `g_pfo_links` | :2502 | `__param_consumed`, `__pfo_lend_note` |  |
| `g_pfo_via` | :2501 | `__mem_payload_local_lend1`, `__pfo_lend_note`, `mem_join_local_lend`, `mem_ret_local_lend` |  |
| `g_pk_cond_any` | :2883 | `__pderiv_params` | …and whether any `%K:callee:k` condition was made (__pk_note): only then are the keep summaries settled before |
| `g_pk_last` | :2871 | `mem_arg_consumption` | The parameters a call keeps of its arguments (__pk_note): the value it hands back may hold them — read by __pd |
| `g_pkgver_memo` | :25178 | `__lx_is_space` | ── `( pkg_version )` ───────────────────────────────────────────  `( pkg_version )` is the `version` of the pa |
| `g_pl_chain_depth` | :2498 | `__pl_chain_sub` | How deep __mem_payload_local_lend1 follows a root that is itself a lend. |
| `g_pl_memo` | :2503 | `__pl_chain_sub` |  |
| `g_pl_qid` | :2499 | `__pl_chain_sub` |  |
| `g_pl_seen` | :2887 | `gen_foreach`, `mem_note_plend`, `mem_note_plroot`, `resolve_clone_hooks` | …and whether a `??` payload or a `~` loop element has been bound in it (`__plend` / `__plroot` / `__econt`): o |
| `g_pmove_n` | :4164 | `__mem_udrop_bind_flag`, `resolve_clone_hooks` | How many bindings of the function being compiled took over a `% Drop` parameter's own value (`: R q p`, `__pmo |
| `g_pp` | :536 | `__pp_init` |  |
| `g_pp_ix` | :537 | `__pp_init` |  |
| `g_priv_file_count` | :2054 | `priv_file_id` |  |
| `g_priv_file_ids` | :2053 | `__target_arch` | `??`/`?` arms). Consumers that NEED a value (a cast, a let/assign) die with this appended, so "produced no val |
| `g_priv_owner_files` | :2056 | `__target_arch` |  |
| `g_priv_owner_ids` | :2055 | `__target_arch` |  |
| `g_priv_warned` | :2057 | `__target_arch` |  |
| `g_pt_star` | :1468 | `parse_type_paren`, `parse_type_ptr` | Raw-pointer types parse_type has read (`*T` anywhere but inside a closure type): a struct field whose type mov |
| `g_ptr_own_n` | :2314 | `__ptr_own_set`, `resolve_clone_hooks` |  |
| `g_ptrtab` | :2237 | `__target_arch` |  |
| `g_raw_fns` | :3837 | `scan_fn_sigs` | `raw @ f …` (grammar v2.9): f's body may use raw memory, as an `unsafe` one's may, and f's CALLER must vouch f |
| `g_raw_probe` | :260 | `__raw_call_die`, `bck_check_raw_call` |  |
| `g_rawlit_n` | :2317 | `mem_note_rawlit`, `resolve_clone_hooks` |  |
| `g_rawlit_pending` | :2316 | `__mb_tmp_flag`, `mem_note_rawlit`, `mem_rawlit_unclaimed`, `resolve_clone_hooks` |  |
| `g_rawret_memo` | :47811 | `__fn_raw_ret` |  |
| `g_rbv_memo` | :57252 | `__target_arch` | __rv_bare_params' answers, per callee: a callee's declared parameter types do not change once known (one whose |
| `g_rc_direct_memo` | :2937 | `__dyn_impl_tys` |  |
| `g_rc_idset` | :2943 | `__dyn_impl_tys` |  |
| `g_rc_nsets` | :2944 | `__dyn_impl_tys` |  |
| `g_rc_reach_memo` | :2936 | `bck_elem_keeper` | __rc_reach's answers, per lowered type (the bar list, `-` for none), and __rc_direct's. |
| `g_rc_setid` | :2942 | `__dyn_impl_tys` | The Rc type sets the borrow walk notes, interned: each set is written once, and a note names it by its number  |
| `g_rcp_fall` | :2455 | `__target_arch` | …and the functions a value of which falls off with no row (__bck_fall_ret_record). |
| `g_rcp_on` | :2453 | `mem_arg_consumption` | …asked only once the module has read an Rc's payload (`rc_get`, gen_call): with none read, no value is read th |
| `g_rcv_n` | :51180 | `bck_stash_cdep` | …and a value no binding names, handed to `callee` — a call's result, a literal, a join or a block of such: the |
| `g_repl_edges` | :3020 | `__dyn_virtual_round`, `__thr_unsync_drop`, `mem_arg_consumption` |  |
| `g_res_type_syms` | :1212 | `__target_arch` | ── Res-type NURL tracking (must be declared before parse_type_res) ── g_res_type_syms is initialized to a new  |
| `g_ret_blk_exit` | :7731 | `__ret_blk_exit_flush`, `gen_block_expr` | (A lend a return hands back out of a parameter owned by its drop flag is parked while the return compiles (g_r |
| `g_ret_clo_share` | :2521 | `__csv_has`, `__mb_tmp_flag` |  |
| `g_ret_forbidden` | :1996 | `__gen_stmt_level`, `emit_agg_exit`, `gen_logical_or_bitwise_and`, `gen_logical_or_bitwise_or` +1 | Cascade guard: 1 while parsing a VALUE OPERAND (a binary/unary/cast/ member operand, a call argument, a `?`/`? |
| `g_ret_lit_lex` | :2520 | `__ret_blk_exit_flush` |  |
| `g_ret_lit_pos` | :2519 | `__ret_blk_exit_flush` | Where the literal a `^` hands back starts (`^ @ H { … }`), and the names read in it after a closure literal it |
| `g_ret_lq` | :2500 | `__ret_blk_exit_flush` |  |
| `g_ret_sl_ids` | :4391 | `__ret_blk_exit_flush` | The owned slices a returned join may hand back (their keys) and the value it hands back: mem_drop_owned releas |
| `g_ret_sl_val` | :4392 | `__ret_blk_exit_flush` |  |
| `g_ret_vlex` | :2514 | `__ret_blk_exit_flush` |  |
| `g_ret_vpos` | :2513 | `__ret_blk_exit_flush`, `emit_agg_exit`, `emit_or_chain` | Where the value a `^` hands back starts (a lexer and a token position): the return's operand, and through it a |
| `g_retcap_n` | :2319 | `resolve_clone_hooks` |  |
| `g_retclo_n` | :2318 | `resolve_clone_hooks` |  |
| `g_retcloeff_n` | :2334 | `__rc_share_note` |  |
| `g_retfwdc_n` | :3982 | `__retfwd_chain_note` | How many chained lend notes (`retfwdc##fn`) this module made: none, and the module-end passes ask none (agora  |
| `g_root_syms` | :2470 | `__target_arch` | The module's root symbol table, for the type questions asked where no table is at hand (__is_handle_ty on a st |
| `g_rp_calls` | :2258 | `mem_arg_consumption`, `resolve_clone_hooks` |  |
| `g_rp_d0` | :2257 | `resolve_clone_hooks` | For the function being compiled (agora #386): the block depth of its body's top-level statements (-1: none), a |
| `g_rp_nstmt` | :2272 | `gen_stmt`, `resolve_clone_hooks` |  |
| `g_rp_rd` | :2271 | `__csv_has`, `bck_note_read`, `gen_stmt`, `resolve_clone_hooks` | …and how many reads the top-level statement being compiled has made so far, nested blocks, arms and joins incl |
| `g_rp_sc` | :2266 | `gen_logical_and`, `gen_logical_or` | …and how many `&` / `\|` right operands enclose the code being compiled (__rp_apply), and how many statements o |
| `g_rpg_bw` | :3951 | `emit_or_chain`, `gen_block_expr`, `gen_block_stmts`, `resolve_clone_hooks` |  |
| `g_rpg_cur` | :48199 | `__lend_pending` |  |
| `g_rpg_cur_id` | :48200 | `__lend_pending` |  |
| `g_rpg_cur_pfx` | :48201 | `__lend_pending` |  |
| `g_rpg_ecap` | :48222 | `resolve_pending_ret_escapes` |  |
| `g_rpg_edge` | :48220 | `resolve_pending_ret_escapes` |  |
| `g_rpg_f` | :48217 | `__lend_pending` | A function's row, RPG_FW words: 0 its name (a copy), 1 1 when it has records, 2 what its other summaries say i |
| `g_rpg_fcap` | :48219 | `__lend_pending` |  |
| `g_rpg_fid` | :48202 | `__lend_pending` |  |
| `g_rpg_list` | :81919 | `__raw_writer` | The records of function `f`, in order: g_rpg_list[ row 11 .. next ). |
| `g_rpg_litv` | :3952 | `__mb_tmp_flag`, `resolve_clone_hooks` |  |
| `g_rpg_me_id` | :48237 | `resolve_clone_hooks`, `resolve_pending_ret_escapes` |  |
| `g_rpg_me_self` | :48236 | `resolve_clone_hooks` |  |
| `g_rpg_names` | :48198 | `__lend_pending` |  |
| `g_rpg_nedge` | :48221 | `resolve_pending_ret_escapes` |  |
| `g_rpg_nfn` | :48218 | `__lend_pending` |  |
| `g_rpg_nown` | :48230 | `__raw_writer` |  |
| `g_rpg_nrec` | :48191 | `__lend_pending` |  |
| `g_rpg_nslot` | :48196 | `__lend_pending` |  |
| `g_rpg_nuns` | :48232 | `__fn_sync_params` |  |
| `g_rpg_on` | :3939 | `resolve_clone_hooks` | …and its graph is recorded (g_rpg): raw code with a parameter that can hold storage. Without one, nothing the  |
| `g_rpg_oret` | :3959 | `resolve_clone_hooks` | g_rpg_oret: the function compiling is raw code that hands back such a value — the only place what its values A |
| `g_rpg_ovreads` | :3956 | `__ret_blk_exit_flush`, `__rpg_oname`, `gen_block_expr`, `resolve_clone_hooks` | g_rpg_ovreads: g_rpg_vreads' twin where raw code is compiled, for a value that owns something — what it IS (__ |
| `g_rpg_own` | :48229 | `__raw_writer` | The thread rules' reading of rows 7 and 8 (__thr_unsync_change). What each function changes itself, before a c |
| `g_rpg_rcap` | :48192 | `__lend_pending` |  |
| `g_rpg_rec` | :48190 | `__lend_pending` |  |
| `g_rpg_scap` | :48197 | `__lend_pending` |  |
| `g_rpg_sname` | :48195 | `__lend_pending` |  |
| `g_rpg_swant` | :3950 | `__gen_stmt_level`, `resolve_clone_hooks` |  |
| `g_rpg_tmp` | :48538 | `__rprov_lend_expr`, `__rprov_oret_bind`, `__rprov_ret_bind` | A returned pointer (or a returned literal's pointer field) whose expression read `reads`: bound to a name of i |
| `g_rpg_u` | :48194 | `__lend_pending` |  |
| `g_rpg_unsync` | :48231 | `__fn_sync_params` |  |
| `g_rpg_v` | :48193 | `__lend_pending` |  |
| `g_rpg_vreads` | :3948 | `__gen_stmt_level`, `__ret_blk_exit_flush`, `__rpg_call_summarised`, `gen_block_expr` +1 | What the value of the statement just compiled reaches, where the graph is recorded: noted when its consumer as |
| `g_rpg_want` | :3949 | `__gen_stmt_level`, `__ret_blk_exit_flush`, `emit_agg_exit`, `emit_or_chain` +4 |  |
| `g_rprov_on` | :3930 | `resolve_clone_hooks` | Raw provenance is followed in this body (__rprov_note): it is raw code, an `unsafe` function or the trusted st |
| `g_s_catches` | :608 | `eng_apply_call`, `eng_check_fn` |  |
| `g_s_cloargs` | :491 | `call_closure`, `eng_check_fn` |  |
| `g_s_consumes` | :485 | `eng_check_fn`, `move_out`, `run_closures`, `stmt_ret` +1 |  |
| `g_s_credits` | :490 | `eng_check_fn`, `stmt_assign` |  |
| `g_s_detaches` | :488 | `eng_apply_call`, `eng_check_fn` |  |
| `g_s_effects` | :484 | `eng_apply_call`, `eng_check_fn`, `eng_effect` |  |
| `g_s_elems` | :486 | `eng_apply_call`, `eng_check_fn` |  |
| `g_s_invokes` | :487 | `call_closure`, `eng_apply_call`, `eng_check_fn` |  |
| `g_s_regions` | :492 | `eng_check_fn`, `eng_effect`, `region_effect` |  |
| `g_s_selfholds` | :493 | `eng_check_fn`, `eng_transfer` |  |
| `g_s_stale` | :489 | `eng_check_fn`, `eng_read` |  |
| `g_sanitize_address` | :105667 | `__target_arch` | Emission policy, set by main's --sanitize-address flag. |
| `g_sealed_views` | :2327 | `__sealed_view_bind` |  |
| `g_seen_par` | :89819 | `__vec_drop_fn` | …and who first queued a key in its walk (__seen_parent): the path back to the question a yes was found on. |
| `g_seen_stamp` | :89816 | `__vec_drop_fn` |  |
| `g_seen_tab` | :89815 | `__vec_drop_fn` | A visited set per question without a table per question: each walk takes a fresh stamp (__seen_begin), and a k |
| `g_sh_pend` | :2858 | `mem_arg_consumption` | A sealed representation's field handed to a function of the program not compiled yet: whether it changes that  |
| `g_sh_pend_n` | :2859 | `mem_arg_consumption` |  |
| `g_simd_defer` | :4438 | `__target_arch` | `simd` functions held back until the module is complete (defer_multiversion): `<k>.ir` / `.n` / `.r` / `.p` →  |
| `g_simd_defer_n` | :4439 | `__target_arch`, `defer_multiversion`, `flush_simd_deferred` |  |
| `g_simd_fns` | :4430 | `__crypto_fn_ir` | Every `simd` function emit_multiversion has written, by its IR name (`__nurl_fn.f`), space-separated. The spli |
| `g_sk_seen` | :93936 | `emit_cc_trace_fn` | Does a value of type `ty` reach such a handle, or a closure (whose captures its type does not name)? Memoised; |
| `g_sm` | :538 | `__pp_init` |  |
| `g_sm_cur` | :592 | (init only) |  |
| `g_sm_dyn` | :583 | `eng_main` |  |
| `g_sm_edges` | :611 | `eng_check_module` |  |
| `g_sm_rd_head` | :618 | `eng_check_module` |  |
| `g_sm_readers` | :612 | `eng_check_module` |  |
| `g_sm_stamp` | :610 | `eng_check_module` |  |
| `g_sm_tmp` | :540 | `__pp_init` |  |
| `g_sm_version` | :600 | `eng_make_summary` |  |
| `g_sm_w` | :539 | `__pp_init` |  |
| `g_sound` | :51754 | `bck_sound` | The sound-and-complete rules (docs/SOUND_COMPLETE_PLAN.md): moves and borrows. Under development they run when |
| `g_source_snapshots` | :105676 | `__dce_index_of`, `__target_arch` |  |
| `g_sp_buf` | :83399 | `__tb_body` | The spaces that put the first token of a re-lexed template line at its SOURCE column (__tb_pad). Tokens are jo |
| `g_sp_pin` | :108768 | `__sp_whole` |  |
| `g_sp_pq` | :108769 | `__sp_whole` |  |
| `g_sp_pqn` | :108770 | `__sp_whole` |  |
| `g_sp_rchg` | :105367 | `__sp_whole` |  |
| `g_split_fh` | :105385 | `__sp_emit_global` |  |
| `g_split_fill` | :105363 | `__sp_target` |  |
| `g_split_max` | :105357 | `__target_arch` |  |
| `g_split_min` | :105358 | `__target_arch` |  |
| `g_split_n` | :105356 | `__sp_parts`, `__sp_target`, `__sp_whole` | Partitioned emission — see "Partitioned emission" below. |
| `g_split_name` | :105360 | `__sp_emit_global` |  |
| `g_split_out` | :105359 | `__target_arch` |  |
| `g_split_part` | :105362 | `__sp_target` |  |
| `g_split_priv` | :105364 | `__sp_target` |  |
| `g_split_rep` | :105365 | `__sp_target` |  |
| `g_split_repmask` | :105366 | `__sp_target` |  |
| `g_sq` | :278 | `__eng_ice` |  |
| `g_sq_cap` | :280 | `__eng_ice` |  |
| `g_sq_ht` | :281 | `__eng_ice` |  |
| `g_sq_ht_cap` | :282 | `__eng_ice` |  |
| `g_sq_ht_n` | :283 | `__eng_ice` |  |
| `g_sq_memo` | :287 | `__eng_ice` |  |
| `g_sq_n` | :279 | `__eng_ice` |  |
| `g_sq_tmp` | :284 | `__eng_ice` |  |
| `g_sq_tmp_cap` | :286 | `__eng_ice` |  |
| `g_sq_tmp_n` | :285 | `__eng_ice` |  |
| `g_srcx_on` | :4248 | `resolve_clone_hooks` | Source expressions (srcx): where a view's value came from, as an expression the walk evaluates once every summ |
| `g_st_free` | :445 | `st_copy`, `st_new` |  |
| `g_stmt_bare_lit` | :9780 | `__gen_stmt_level` | g_stmt_bare_lit — set by gen_stmt to 1 when the statement it just parsed was a bare numeric/string LITERAL in  |
| `g_stmt_bare_value` | :9807 | `__gen_stmt_level` | g_stmt_bare_value — the literal flag's general sibling (critic A2, the last silent prefix-arity cascade): set  |
| `g_stmt_col` | :9613 | `__gen_stmt_level`, `gen_block_ret`, `gen_block_stmts` | g_stmt_col — column of the current statement's first token, captured alongside g_stmt_line. `die_stmt` anchors |
| `g_stmt_lex` | :9619 | `__gen_stmt_level`, `__lx_is_space` | g_stmt_lex — the lexer that statement came from, so a check deep in codegen that has no lexer of its own (__nc |
| `g_stmt_line` | :9606 | `__gen_stmt_level`, `gen_block_ret`, `gen_block_stmts` | g_stmt_line — source line of the statement gen_stmt is currently parsing. Read by gen_ident's "unexpected toke |
| `g_str_idx` | :1956 | `emit_deferred_cstr`, `emit_str_global`, `gen_str_lit` |  |
| `g_str_syms` | :1957 | `__target_arch` |  |
| `g_strict_arity` | :2227 | `__target_arch` | strict-arity: the n-ary `&`/`\|` arity trap is an ERROR by default. The trap is the language's one documented f |
| `g_strict_borrowck` | :2215 | `__target_arch` | `--strict-borrowck` (off by default) enables three additional checks: (1) aliased mutation through `. obj fiel |
| `g_struct_inst_syms` | :2019 | `__target_arch` | <sname>__stparams → space-separated type-var names (e.g. "T" or "K V") <sname>__sbody    → raw body source inc |
| `g_struct_ll` | :4456 | `__target_arch` | Every struct's LLVM field types, by IR name (`%` dropped), as its body lists them: what __ty_has_wide asks whe |
| `g_struct_tmp` | :2802 | `__csv_has`, `mem_arg_consumption`, `mem_clo_drop_discarded`, `resolve_clone_hooks` | The struct temporary with owned fields most recently returned by a call, as `<value> <%Type> <owned-field toke |
| `g_summaries_final` | :2287 | `mem_emit_arg_flags` |  |
| `g_super_obligations` | :2125 | `__coherence_register` |  |
| `g_sx` | :4407 | `__sx_enter` |  |
| `g_sx_at` | :4406 | `__sx_enter` |  |
| `g_sx_ix` | :597 | `sx_new` |  |
| `g_sx_n` | :4405 | `__sx_enter` |  |
| `g_sx_next` | :598 | `eng_prims_once`, `sx_new` |  |
| `g_sx_none` | :599 | `sx_new` |  |
| `g_sx_virt` | :601 | `sx_new` |  |
| `g_sx_virt_at` | :602 | `sx_new` |  |
| `g_sxe_arc` | :2963 | `__ah_raise`, `__match_arc_mark`, `bck_arc_frozen_check`, `bck_borrow_begin` +4 | At the borrow walk: whether the value of the source expression being evaluated is a view of an Arc's payload — |
| `g_sxe_pos` | :53478 | `__src_mark`, `__sx_name_roots`, `bck_sx_arg_held`, `bck_sx_arg_sources` +8 | ── Source expressions in the walk ── The cursor of the evaluation in progress (bck_sx_sources), and whether it |
| `g_sxe_rvn` | :53511 | `__rvsrc_add`, `bck_ret_view_check`, `bck_walk_seq` | …and the sources a callee's walk answered its result views only through their elements (`2`, __rv_ask) in the  |
| `g_sxe_rvtab` | :53512 | `__rvsrc_add` |  |
| `g_sxr_n` | :51263 | `__bck_sxr_note` | The lent arguments a call's walk reads where it runs (agora #604): the arguments of `( two ( string_data s ) ( |
| `g_sync_params_memo` | :48234 | `__fn_sync_params` |  |
| `g_syncrun_any` | :2974 | `__sync_req_params`, `resolve_send_checks` | Whether any parameter is run on several threads at once (`syncrun##`, resolve_send_checks): until one is, its  |
| `g_tail_reg` | :1962 | `__csv_has`, `emit_ret_value`, `mem_arg_consumption`, `resolve_clone_hooks` | The register the last `tail call` put its result in (gen_call): a return of exactly that value keeps its own ` |
| `g_target_x86` | :4491 | `__target_arch` | Is the module for x86-64? The native default is the host's architecture, `--target=` names another, `--cpu-dis |
| `g_tb_buf` | :83435 | `__tb_body` | ── Template text, built in one buffer ───────────────────────────── A function body kept for later (a generic  |
| `g_tb_cap` | :83436 | `__tb_body` |  |
| `g_tb_top` | :83437 | `__tb_body` |  |
| `g_tf_body` | :108050 | `__ir_write_range` |  |
| `g_tf_en` | :108049 | `__ir_write_range` |  |
| `g_tf_map` | :108052 | `__ir_write_range` |  |
| `g_tf_olen` | :108054 | `__ir_write_range` |  |
| `g_tf_out` | :108053 | `__ir_write_range` |  |
| `g_tf_st` | :108048 | `__ir_write_range` | ── Type definitions first ──────────────────────────────────────────  A named struct is printed where the gene |
| `g_tf_state` | :108051 | `__ir_write_range` |  |
| `g_thv_final` | :2324 | `__target_arch` |  |
| `g_thv_memo` | :2323 | `__ty_own_view_p` |  |
| `g_thv_own` | :2322 | `__ty_own_view_p` |  |
| `g_thv_precise` | :2320 | `__held_fallback`, `__is_clo_capture`, `__mb_tmp_flag`, `__note_vcopy` +6 |  |
| `g_thv_unknown` | :2325 | `__thv_named`, `__ty_own_view_p` |  |
| `g_trait_pending` | :2108 | `__target_arch` | <Trait>__tparam           → trait's generic type-var name (e.g. "T") <Trait>__defaults         → space-separat |
| `g_trait_syms` | :2094 | `__target_arch` | first registration. A `$`-imported impl is scanned once per importer, so the SAME (method, type) is registered |
| `g_trust_memo` | :47691 | `__trust_root` | ── Raw memory and `unsafe` (docs/SOUND_COMPLETE_PLAN.md, P1) ───────  The stdlib is the vouched-for base: its  |
| `g_trust_roots` | :47692 | `__trust_root` |  |
| `g_ts_seen` | :91404 | `__res_children` | The thread-shared nodes a value of type `ty` holds (`\|` list; `*` for a closure). (A question's walk: each typ |
| `g_type_count` | :2186 | `__target_arch`, `store_closure_type` |  |
| `g_type_emit_base` | :2189 | `__target_arch` |  |
| `g_type_layouts` | :2707 | `__target_arch` | Type layout metadata precedes cleanup decisions; IR definitions retain their source ordering. This table owns  |
| `g_udrop_noinit` | :2614 | `__mb_tmp_flag`, `__sb`, `__shadow_reset`, `emit_or_chain` | Set by a `:` binding just before registering its value: the binding rule stores the drop flag itself, so regis |
| `g_udrop_tmpown` | :2665 | `__mb_tmp_flag`, `__sb`, `emit_or_chain` | Set by a call's temporary given an owner of its own (h233, h330) just before registering it: its journal regis |
| `g_unsafe_fns` | :3833 | `gen_dyn_construct`, `scan_fn_sigs` | The functions declared `unsafe` (name → 1; 0 until the first one). |
| `g_unsafe_list` | :3896 | `mem_velem_tag` |  |
| `g_unsafe_report` | :3895 | `__target_arch` |  |
| `g_use_argxfer` | :2479 | `mem_emit_string_arg_transfers`, `mem_sink_str_arg` |  |
| `g_use_clear_if` | :2473 | `mem_udrop_flag_clear_if` | Whether this module calls the drop-flag helpers (emitted at module end). |
| `g_use_clo_cloneif` | :2775 | `__clo_tmp_settle`, `__ret_blk_exit_flush`, `mem_retclo_take_call` | Is __nurl_clo_cloneif used (emitted at module end)? |
| `g_use_drop_range` | :2489 | `gen_mem_drop_range`, `gen_mem_move_drop` | A module that drops a range of elements (`mem_drop_range`), or a Vec whose elements may run a destructor of th |
| `g_use_hown` | :2480 | `emit_dyn_method_thunk`, `mem_capture_hown`, `mem_publish_hown` |  |
| `g_use_jdrop_rawstr` | :2495 | `mem_ret_guard_rawstr` | A fresh raw string result was journaled by its slot (mem_ret_guard_raw): `@__jdrop_rawstr`, its thunk, is writ |
| `g_use_jslice` | :2492 | `mem_journal_push_slice_buf` | A slice that owns its elements was journaled with them (nurl_journal_push_slice, agora #509): declared at modu |
| `g_use_ownstr` | :191 | `__ret_blk_exit_flush`, `mem_clo_ret_own_str` |  |
| `g_use_sinkstr` | :188 | `mem_sink_str_arg` |  |
| `g_use_slot_take` | :2483 | `mem_vget_consume`, `mem_vget_field_consume` | A vec_get payload taken out by its own bytes (nurl_vec_slot_take_if): its declaration, emitted at module end o |
| `g_use_sltmask8` | :192 | `mem_propagate_call_ret_markers` |  |
| `g_use_taken_check` | :2475 | `__clo_taken_check` | …and the taken-capture check (__clo_taken_check, agora #463). |
| `g_use_vec_drop_dtor` | :2496 | `__vec_drop_fn` |  |
| `g_user_drop_seen` | :698 | `__coherence_register`, `emit_dyn_drop_fn` | 1 once the program declares a `% Drop` impl of its own (scan_impl_decl): until then no type has one, and the q |
| `g_ut_gen` | :4002 | `bck_unsafe_ctx` |  |
| `g_vb_arm_pub` | :4182 | `emit_agg_exit`, `emit_or_chain` | The next `?` / `??` is a bare arm of a join in a value block (agora #836): it publishes what its arms lent for |
| `g_vb_marks` | :2988 | `__vb_close`, `resolve_clone_hooks` |  |
| `g_vb_on` | :2986 | `gen_block_expr` | A value block's names end at its `}` (agora #575; the helpers and the account are above gen_block_expr). |
| `g_vb_sd` | :2987 | `gen_block_expr` |  |
| `g_vcall` | :4457 | `__target_arch` |  |
| `g_vcall_n` | :4458 | `__target_arch`, `__vcall_thunk` |  |
| `g_vcall_site` | :4459 | `__vcall_thunk` |  |
| `g_vctl_seen` | :3861 | `mem_arg_consumption`, `mem_note_velem`, `resolve_clone_hooks` | Set by a call to nurl_vctl_data; the let that binds its result marks the pointer `__velem` (its element access |
| `g_vis_file_gen` | :4001 | `vis_set_current_src_file` |  |
| `g_vis_inst_targs` | :3122 | `__ty_memo_forget` | The type arguments of the generic struct being instantiated (its field types are parsed in a pseudo-file); see |
| `g_vis_readback` | :3127 | `__libh_targ` | Nonzero while the compiler reads back a type it recorded itself (a library handle's type argument, __libh_targ |
| `g_vis_syms` | :3819 | `__target_arch` |  |
| `g_vk_assume_on` | :686 | `bck_diag_vbuf_self`, `nurlc_print_help` | While the parked walks run (resolve_deferred_borrowck), a `dyn` impl whose walk has not answered yet is taken  |
| `g_vk_assumed` | :687 | `__vk_of_d`, `bck_diag_vbuf_self` |  |
| `g_vk_assumptions` | :688 | `bck_diag_vbuf_self` |  |
| `g_void_reason` | :2023 | `__void_reason_clear`, `emit_agg_exit`, `emit_or_chain`, `int_width` |  |
| `g_vp_active` | :4125 | `mem_arg_consumption` | …and the call whose arguments are being compiled now (0: none): a call nested in another's arguments keeps its |
| `g_vp_seq` | :4122 | `mem_arg_consumption` |  |
| `g_vp_tag` | :4121 | `mem_arg_consumption` | The call whose own `vpass` rows are being stashed (0: none). Their line field is `LINE.SEQ` then: atoll reads  |
| `g_walk_owns` | :268 | `__target_arch` |  |
| `g_wide_struct` | :4462 | `__note_struct_field` | Set once a struct field is itself a wide vector: from then on every function is looked at for indirect calls p |
| `g_win_done` | :2786 | `__csv_has`, `bck_flush_moves`, `mem_arg_consumption`, `resolve_clone_hooks` | Calls completed since the walk last recorded a statement's effects. |
| `g_ws_syms` | :604 | `eng_main` |  |
| `g_wv` | :274 | `__eng_ice` | ── Ownership engine (docs/dev/CORE_IR.md §7, AGORA-863) ───────────── The rule table of tools/ncore/RULES.md o |
| `g_wv_cap` | :276 | `__eng_ice` |  |
| `g_wv_freed` | :277 | `__eng_ice` |  |
| `g_wv_n` | :275 | `__eng_ice` |  |
| `g_xl_cap` | :4416 | `bck_xl_resolve` |  |
| `g_xl_depth` | :4412 | `bck_xl_declare`, `bck_xl_resolve` | The frame depth and renames of the lexical scopes the borrow walk's rows are translated in (bck_xl_declare_id) |
| `g_xl_nser` | :4417 | `bck_xl_declare`, `bck_xl_resolve` |  |
| `g_xl_op` | :4415 | `bck_xl_resolve` |  |
| `g_xl_ren` | :4413 | `bck_xl_resolve` |  |
| `g_xl_ss` | :4414 | `bck_xl_resolve` |  |

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
build it from `nurlc_lastgood.ll` with nothing but clang). There is **no
AST and no IR data structure**: parsing, type checking, borrow checking
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
| `g_agg_arg_lend` | :3005 | `mem_arg_consumption` | 1 while the call argument being compiled is an aggregate literal its callee may hand back whole (gen_call); ge |
| `g_arcp_any` | :1926 | `__arcp_note` | Whether any callee takes an Arc (`arcp##`, §6.5), and whether the function being compiled has handled one (gen |
| `g_arg_dyn_box` | :1733 | `gen_dyn_construct`, `mem_arg_consumption`, `mem_arg_temps` | An argument that is `( dyn Trait v )`: the box is a temporary of the call (mem_arg_temps); gen_dyn_construct s |
| `g_arg_ident_log` | :1462 | `mem_arg_consumption`, `store_global` | --strict-borrowck only: every binding NAME read while generating the current call argument, including reads ne |
| `g_arg_join_set` | :1742 | `mem_arg_consumption`, `mem_arg_temps` | Set when a `?` / `??` argument's ownership bit waits in `__argtmp_joinown__` for mem_arg_temps (agora #174): t |
| `g_arg_litown_set` | :1737 | `mem_arg_consumption`, `mem_arg_temps` | Set when a literal argument's owned fields wait in `__argtmp_litown__` for mem_arg_temps: the symbol is writte |
| `g_arm_qval` | :3013 | `emit_or_chain`, `mem_join_heads_stmt` | 1 from gen_match to the `?` / `??` that is an arm's whole value, in a match whose value is taken: that join's  |
| `g_arm_valu` | :3009 | `emit_or_chain`, `mem_join_heads_stmt` | 1 while mem_arm_hown asks about an arm of a join whose value is taken (gen_cond's c_valu, gen_match's m_val):  |
| `g_at` | :65007 | `__ext_calls_back` | ── Which functions run inside a recover extent ───────────────── |
| `g_auto_drop_strings` | :2761 | `__target_arch` | Phase 2B auto-drop-strings feature flag. Default ON. Compiler's own source uses patterns (strings stored via n |
| `g_bck` | :1550 | `__target_arch` |  |
| `g_bck_ab_any` | :1942 | `bck_analyze`, `bck_borrow_begin` | Whether any borrow of this function's walk is one of a payload (`ab_`). |
| `g_bck_bind_scalar` | :26198 | `bck_flush_moves` | Set by bck_record_binding for its row: 1 when the binding holds no heap value and no address (a scalar), so no |
| `g_bck_bind_sown` | :26206 | `__assign_result_lent`, `__names_type`, `bck_flush_moves` | …and 1 when it is an `s` that owns the buffer it points at (field 5 `o`): a tracked owned string, every assign |
| `g_bck_bind_wview` | :26200 | `bck_flush_moves` | …and 1 when that view owns nothing (field 5 `w`, bck_record_binding). |
| `g_bck_cap_names` | :1484 | `__csv_has`, `bck_clear_cap_name`, `bck_fn_begin` | Names of `:`-bound closures in the CURRENT function whose capture list is non-empty — the allocation-free pre- |
| `g_bck_cap_via` | :1495 | `__csv_has`, `bck_defer_fn`, `bck_fn_begin`, `bck_opaque_param_run` | `<handle> <closure>` pairs for the current function: which closure binding made a captured handle reachable at |
| `g_bck_close` | :29284 | `bck_kill_stored_in_d` | The close marker of every open marker, found once per walk with a stack per bracket kind: the walk asks for th |
| `g_bck_closure_depth` | :1623 | `__csv_has` |  |
| `g_bck_cw0` | :2910 | `bck_cursor_watch` |  |
| `g_bck_cw1` | :2911 | `bck_cursor_watch` |  |
| `g_bck_cw2` | :2912 | `bck_cursor_watch` |  |
| `g_bck_cw3` | :2913 | `bck_cursor_watch` |  |
| `g_bck_cwn` | :2909 | `bck_cursor_watch` | …and the ids a row may concern them through (bck_cursor_watch): up to four in `g_bck_cw0`…`g_bck_cw3` (`g_bck_ |
| `g_bck_depth` | :1561 | `__csv_has`, `bck_block_enter`, `bck_block_exit`, `bck_fn_begin` |  |
| `g_bck_dser` | :3043 | `bck_alias_step` |  |
| `g_bck_end_eonly` | :2917 | `bck_borrow_sweep` | Set while a borrow end comes from elements dropped or replaced (not the value itself): an owner holding a clos |
| `g_bck_errors` | :1627 | `__ptr_stale_warn`, `__ptr_stale_warn_at`, `bck_kill_stored_in_d` | capture hooks no-op so closure statements do not inline into the enclosing function's list (so closure scopes  |
| `g_bck_fevar` | :1694 | `bck_block_enter`, `bck_fn_begin`, `gen_foreach` | A `~ x xs` loop's element binding is waiting for its body's block row (`pending_fevar` in g_bck names it). |
| `g_bck_gen` | :1592 | `bck_analyze` |  |
| `g_bck_has_borrow` | :28304 | `bck_analyze`, `bck_borrow_begin`, `bck_dep_add`, `bck_walk_seq` | Set once a function records a borrow: only then does the walk compare states row by row to end borrows whose s |
| `g_bck_has_cursor` | :2905 | `bck_analyze`, `bck_handle_match` | …and whether it has bound a `??` arm's payload as a cursor over the option binding it matched (bck_handle_matc |
| `g_bck_has_defers` | :1598 | `bck_analyze` |  |
| `g_bck_has_deps` | :2902 | `bck_analyze`, `bck_dep_add` | Whether this function's walk has recorded any view dependency (bck_dep_add), and statement `vpass` rows pendin |
| `g_bck_has_paths` | :28306 | `bck_alias_step`, `bck_analyze` | Set once a function interns a field path (`s.items`, bck_intern). |
| `g_bck_inew` | :3044 | `bck_alias_step` |  |
| `g_bck_inn` | :1596 | `bck_alias_step`, `bck_analyze` | intern table — bumped per bck_analyze so entries from earlier functions read as misses without any table clear |
| `g_bck_iter_live` | :3020 | `__csv_has`, `bck_fn_begin`, `bck_iter_enter`, `bck_iter_exit` | 1 while the code being compiled sits in a `~` loop over a container (`iter_containers` in g_bck is not empty): |
| `g_bck_jn` | :1558 | `bck_analyze`, `bck_log_close`, `bck_log_open` | Open walk logs (walks a loop's fixpoint is watching), innermost last. |
| `g_bck_jopaque` | :1560 | `bck_note` | g_bck writes the journal could not record (a key with a space); each counts as a change (bck_fp). |
| `g_bck_jt` | :1556 | `bck_analyze` | The walk's fact journal (bck_note, bck_log_open / bck_log_close): `<level>\|<key>` → the key's value hash when  |
| `g_bck_let_sx_last` | :1569 | `__assign_result_lent`, `__names_type` | The last `let`'s right-hand source expression (g_bck_rhs_sx), kept past its row: a join it bound is followed b |
| `g_bck_match_sx` | :1944 | `bck_record`, `emit_or_chain` | The source expression of the call a `match` row matches (gen_match). |
| `g_bck_nch_any` | :29612 | `__src_mark_nc`, `bck_analyze` | …and whether any handle copy was marked one an owner cannot copy in (`nch_`, __src_mark_nc) — none: __src_drop |
| `g_bck_nrows` | :28313 | `bck_kill_stored_in_d` |  |
| `g_bck_own_params` | :175 | `bck_defer_fn` |  |
| `g_bck_ownerless` | :1590 | `bck_flush_moves`, `bck_stash_store`, `bck_take_owner_stores` |  |
| `g_bck_pcap` | :28319 | `bck_alias_step` |  |
| `g_bck_pm_slot` | :13650 | `__strget_loop_warn` |  |
| `g_bck_pn` | :28318 | `bck_alias_step` |  |
| `g_bck_pr` | :28317 | `bck_alias_step` | Per id of the function analysed now: the binding it belongs to (itself unless a field path) and a path's spell |
| `g_bck_pvpass_n` | :2918 | `bck_flush_vpass`, `bck_side_lists_put`, `bck_side_lists_take`, `bck_stash_arcx` +2 |  |
| `g_bck_rcap` | :28314 | `bck_kill_stored_in_d` |  |
| `g_bck_rcty` | :181 | `__csv_has`, `bck_defer_fn`, `bck_elem_keeper`, `bck_fn_begin` | The bindings and field paths of the function being walked that hold an `Rc` handle, as `name=type` words (bck_ |
| `g_bck_rd_slot` | :13649 | `__strget_loop_warn` | Byte length of one of g_bck's statement lists (`reads`, `pmoves`) in O(1): g_bck is one flat scope that never  |
| `g_bck_rec_off` | :1610 | (init only) | >0 while the borrow checker's capture hooks must not record. Used to be spelled `g_bck_closure_depth != 0`, wh |
| `g_bck_ret_dep` | :3029 | `mem_note_ret_clo_cap` |  |
| `g_bck_ret_guard` | :1597 | `bck_walk_seq` |  |
| `g_bck_ret_line` | :1599 | `bck_walk_seq` |  |
| `g_bck_ret_sx` | :3028 | `mem_note_ret_clo_cap` | The source expression of a returned view (field 8 of its `ret` row), and 1 when it is an owner returned by nam |
| `g_bck_rhs_callee` | :26212 | `__assign_result_lent`, `__names_type` | The call a `let` / `assign` binds the result of (field 6 of its row): a lend the walk learns from the callee's |
| `g_bck_rhs_lend` | :26618 | `__assign_result_lent`, `__names_type` | Set by a binding whose right-hand side is a call: the sources a borrow of its result has (bck_call_lend_srcs); |
| `g_bck_rhs_path` | :2974 | `__assign_result_lent`, `__names_type`, `bck_note_borrow` | …and the path a binding's field-read right-hand side named (`: T n . h name` → `h.name`): what a borrow decide |
| `g_bck_rhs_sx` | :26215 | `__assign_result_lent`, `__names_type` | The source expression of a `let` / `assign`'s right-hand side (field 8 of a view's row, g_srcx_on): its source |
| `g_bck_rk` | :28312 | `bck_kill_stored_in_d` | …and each row's kind code (bck_kind_code). |
| `g_bck_rlen` | :28310 | `bck_kill_stored_in_d` |  |
| `g_bck_rows` | :28309 | `bck_kill_stored_in_d` | The rows of the function being walked (bck_explode / bck_rec): copies and their lengths. |
| `g_bck_sc` | :3049 | `bck_ids_end` |  |
| `g_bck_sc_cap` | :3048 | `bck_ids_end` |  |
| `g_bck_sc_n` | :3047 | `bck_ids_end`, `bck_walk_seq` | The blocks the walk is in, innermost last (bck_scope_push): rows [lo, hi) of each, and whether it is a loop's  |
| `g_bck_sx_gen` | :1591 | `bck_walk_seq` |  |
| `g_bck_view_reads` | :26208 | `bck_flush_moves` | What a view binding's right-hand side read (bck_record_binding). |
| `g_bcls_memo` | :2896 | `__target_arch` | A binding class per LLVM type (bck_bind_class), and the trusted-file answer for the current source file (bck_u |
| `g_blk_depth` | :1952 | `__blk_enter` |  |
| `g_blk_froot` | :2931 | `gen_block_expr`, `mem_note_payload_part` |  |
| `g_blk_lets` | :1951 | `__blk_enter`, `__blk_tail_sx` | What the bindings declared in value-position blocks hold (h216): words `D:name=sx` (a `let` at block depth D), |
| `g_blk_scalar_let` | :1697 | `__names_type`, `gen_block_expr` | The `:` binding the next block initialises is a number or a flag (gen_let_or_struct → gen_block_expr, consumed |
| `g_blk_tail_eff` | :2934 | `gen_backslash_expr`, `gen_block_expr`, `gen_try_expr` | …and the first token of its tail statement, through a tail that is itself a block (`^ { … { … ( g x ) } }`: a  |
| `g_blk_tail_lit_col` | :5839 | `gen_block_expr`, `gen_block_ret` |  |
| `g_blk_tail_lit_line` | :5838 | `emit_or_chain`, `gen_block_expr`, `gen_block_ret`, `gen_block_stmts` +1 | g_blk_tail_lit_line/col — the dangling-literal exemption's escape hatch, closed. A bare literal as a value blo |
| `g_blk_val_depth` | :1953 | `__blk_enter` |  |
| `g_body_ends` | :11088 | `body_ends_reset` | Where each brace block ends: "<text identity> <offset of a '{'>" → the offset just past its matching '}'. Ever |
| `g_borrowck` | :1510 | `__target_arch` | ── Borrow-checker state ───────────────────────────────────────── g_borrowck is 1 (ON) by default; `--no-borro |
| `g_call_lend_roots` | :2887 | `gen_mem_dup`, `mem_arg_consumption` |  |
| `g_call_roots` | :2886 | `gen_mem_dup`, `mem_arg_consumption` | The call just generated, when one of its arguments was a field path (`. b items`): its arguments with that fie |
| `g_cast_fresh_in` | :1617 | `__gen_cast_body`, `is_ptr_ty` |  |
| `g_clo_assigned` | :1691 | `__csv_has` | The `: ~` scalars the closure being built assigns (simple_capture_analysis finds them; __gen_closure_expr publ |
| `g_clo_bind_name` | :1724 | `__csv_has`, `__names_type` |  |
| `g_clo_cap_set` | :1589 | `mem_arg_consumption` |  |
| `g_clo_caps_now` | :3024 | `__csv_has` | While a closure body is compiled: what it captured (g_clo_caps_now) and the calls it hands one of them — or a  |
| `g_clo_detach` | :1713 | `__csv_has`, `mem_arg_consumption` | Set by a call compiling a closure literal as the closure a thread or a fiber runs, or by a `:` binding of one  |
| `g_clo_detach_shared` | :1707 | `__csv_has` | The detached closure's captures taken by share (__clo_detach_moves); consumed by gen_closure_expr like the mov |
| `g_clo_lend_set` | :1588 | `mem_arg_consumption` |  |
| `g_clo_scan_assigned` | :1698 | `__clo_scan_struct_obj` |  |
| `g_clo_scan_structs` | :1701 | `__clo_ctx_pop`, `__clo_scan_struct_obj` | The closure body's own bindings of a plain struct type, as the capture scan meets them: a name after `. <one o |
| `g_clo_tmp` | :1818 | `mem_retclo_own_result` | The owned closure temporary most recently produced, as `<value> <env>` (docs/MEMORY.md §7.4): published by a c |
| `g_clolend_n` | :1581 | `mem_note_clo_bind_lend`, `mem_note_clo_lend` |  |
| `g_closure_consumed` | :1474 | `__csv_has`, `bck_assign_alias`, `bck_cap_via_of`, `resolve_clo_nc_rets` | Names a closure BODY consumed. bck_stash_move drops its records while inside a closure — the body's statements |
| `g_closure_defs` | :1496 | `__target_arch` |  |
| `g_closure_effects` | :3025 | `__csv_has`, `bck_cap_via_of` |  |
| `g_closure_emit_base` | :1500 | `__target_arch`, `emit_closure_globals` |  |
| `g_closure_types` | :1497 | `__target_arch` |  |
| `g_cond_depth` | :1548 | `gen_loop`, `mem_join_heads_stmt` | Nesting depth of "we are parsing an enclosing construct's CONDITION". The arity check above fires when a `{` f |
| `g_coverage_link_ir` | :2025 | `__target_arch` |  |
| `g_coverage_meta_id` | :2032 | `dbg_flush` |  |
| `g_coverage_notes` | :2024 | `__target_arch` |  |
| `g_coverage_prefix` | :2023 | `__target_arch` |  |
| `g_cpu_dispatch` | :3098 | `__target_arch` | Which wider ISA the `simd` prefix dispatches to. 1 = x86-64-v3 (AVX2 + BMI2 + FMA), 0 = no dispatch, emit the  |
| `g_crypto_defer` | :3069 | `__target_arch` | Crypto-tier functions held back the same way (emit_fn_ir), and the ones among them that ask to be inlined (`in |
| `g_crypto_defer_n` | :3070 | `__target_arch`, `emit_fn_ir`, `flush_simd_deferred` |  |
| `g_crypto_fns` | :3059 | `__target_arch` | Functions whose own IR uses a hardware crypto primitive, by IR name (emit_fn_ir) — what a deferred `simd` func |
| `g_crypto_inl` | :3071 | `__target_arch` |  |
| `g_crypto_target` | :3108 | `__target_arch` | Which hardware crypto tiers the module is built for: 1 x86-64 (AES-NI + PCLMULQDQ, and the VAES ones), 2 AArch |
| `g_cur_params` | :3000 | `gen_fn_decl` |  |
| `g_cur_ret_llty` | :166 | `gen_fn_decl` | LLVM return type of the function whose body is currently being generated. Diagnostics-only: gen_field_store co |
| `g_dbg_blob_syms` | :2035 | `dbg_init` | module-flag id we might add later |
| `g_dbg_cu_id` | :2038 | `dbg_init` |  |
| `g_dbg_current_file_id` | :2067 | `gen_fn_decl` | defining path for the mono being emitted (the mono's lexer filename is the synthetic `<generic …>`). Set/resto |
| `g_dbg_current_loc` | :2041 | `__csv_has`, `__gen_stmt_level`, `dbg_synth_begin`, `dbg_synth_end` +5 | (0 outside any function) |
| `g_dbg_current_subprogram` | :2039 | `__csv_has`, `dbg_synth_begin`, `dbg_synth_end`, `gen_fn_decl` |  |
| `g_dbg_enabled` | :2022 | `__target_arch` | ── DWARF debug-info state ─────────────────────────────────────── All zero/empty when --g is OFF; emit helpers |
| `g_dbg_file_id` | :2037 | `dbg_init` | flushed at end-of-module by dbg_flush |
| `g_dbg_file_syms` | :2056 | `dbg_init` | uses this instead of `nurl_lex_line` for the !DISubprogram source line. Set by emit_one_instantiation so per-m |
| `g_dbg_next_id` | :2033 | `dbg_alloc_id` |  |
| `g_dbg_override_file` | :2061 | `gen_fn_decl_or_lazy`, `gen_import_decl` | every source file gets its own !DIFile and a subprogram debug-attributes to the file that DEFINES it (imports, |
| `g_dbg_override_line` | :2050 | `gen_fn_decl_or_lazy`, `gen_import_decl` | the type for every local until Phase 6 lays down per-LLVM-type DIBasicType entries indexed by `vt`. |
| `g_dbg_placeholder_ty` | :2046 | `dbg_init` | dbg_init and reused for every fn. Phase 6 will replace with per-fn signature types. |
| `g_dbg_subroutine_ty` | :2043 | `dbg_init` | emit_dbg_eol then omits `, !dbg !N`) |
| `g_dbg_type_syms` | :2094 | `dbg_init` |  |
| `g_dce` | :64510 | `__target_arch` |  |
| `g_dce_at` | :64580 | `__sp_parts` |  |
| `g_dce_end` | :64576 | `__sp_parts` |  |
| `g_dce_keep` | :64521 | `__target_arch` | `--keep=a,b,c` — extra DCE roots.  The pass's root set is `main` plus whatever module-scope constants name. Th |
| `g_dce_live` | :64577 | `__sp_parts` |  |
| `g_dce_map` | :64581 | `__sp_parts` |  |
| `g_dce_mod` | :64573 | `__sp_parts` | The module text, as an integer cast of a BORROWED `s`. Deliberately not a `: ~ s` global: a mutable string glo |
| `g_dce_mod_len` | :64574 | `__sp_parts` |  |
| `g_dce_qn` | :64579 | `__dce_ident_byte`, `__sp_parts` |  |
| `g_dce_queue` | :64578 | `__sp_parts` |  |
| `g_dce_start` | :64575 | `__sp_parts` |  |
| `g_dead_arm` | :2840 | `__ice_report`, `mem_join_heads_stmt` | `--unsafe-report`: what the program asks to be trusted (outside the standard library), one `file:line what` pe |
| `g_dead_payload` | :37259 | `__gen_cast_body` | Set while the payload of a None literal is generated, when that payload is a cast (gen_agg_lit): the one cast  |
| `g_defer_count` | :1326 | `gen_defer`, `gen_fn_decl` |  |
| `g_deferred_bck` | :1863 | `__target_arch` | Functions whose borrow-check walk is parked until the whole module has compiled (see borrowck_fn_end). `n` is  |
| `g_diag_ctx` | :157 | `dyn_sig_parts`, `emit_lit_check`, `gen_import_decl`, `scan_method_signature` +2 | Diagnostic context suffix, appended to every die/warn message while non-empty. Set (and saved/restored — insta |
| `g_diag_recover_active` | :135 | `__ice_report`, `__target_arch` |  |
| `g_did_ret` | :1282 | `__close_dead_block`, `__csv_has`, `__handle_unreachable_stmt`, `__tail_noreturn_close` +9 |  |
| `g_drain_n` | :2942 | `mem_drain_deferred` | How many function exits have emitted the deferred-drop list (mem_drain_deferred) so far: a slot parked after o |
| `g_drop_base` | :2994 | `__target_arch` | Which parameters each safe function may drop or replace the elements of (bck_callee_drops_elems): witnessed wh |
| `g_drop_edges` | :2996 | `__target_arch` |  |
| `g_drop_glue_ty` | :170 | `__csv_has`, `gen_dyn_construct`, `gen_fn_decl` | The LLVM type of the value a `% Drop` impl's `drop` is being compiled for (`%R`), or `` — while set, every exi |
| `g_dyn_dtout` | :1436 | `dyn_method_slot` | dyn_method_decltrait's result rides a global too: its callers sit ABOVE its definition, so an owned return wou |
| `g_dyn_flat_out` | :1430 | `__dyn_flat_reset` | Scratch accumulators for dyn_flat_methods (a NURL fn returns one value, so the recursive supertrait walk threa |
| `g_dyn_flat_seen` | :1431 | `__dyn_flat_reset` |  |
| `g_dyn_needed` | :1427 | `__dyn_unslug` | Dynamic trait objects (`%Trait`, docs/spec.md §4.9). Space-separated set of trait names that appear as a `%Tra |
| `g_env_moved` | :1704 | `__csv_has` | …and, for one that a thread or a fiber will run, the captures it takes over from bindings the function no long |
| `g_env_owns_handles` | :1672 | `__csv_has` | Set around a returned closure literal's env generation: its String / Vec / owning-struct captures move into (a |
| `g_env_released` | :1675 | `__csv_has` | …and, for a closure that releases some captures itself, which (their env field is not dropped again). |
| `g_env_shared` | :1709 | `__csv_has` | …and the same set while that closure's env is built and described. |
| `g_err_count` | :134 | `__diag_abort` |  |
| `g_etake_n` | :3016 | `gen_fn_decl`, `mem_enum_take_note` | Payload bindings of an enum the function being compiled owns (mem_enum_take_note): while 0, nothing asks wheth |
| `g_ext` | :65004 | `__ext_calls_back` |  |
| `g_ext_glob` | :65012 | `__ext_calls_back` |  |
| `g_ext_mlen` | :65013 | `__ext_calls_back` |  |
| `g_ext_q` | :65008 | `__ext_calls_back` |  |
| `g_ext_qn` | :65009 | `__dce_ident_byte`, `__ext_calls_back` |  |
| `g_ext_sig` | :65011 | `__ext_calls_back`, `__ext_types` |  |
| `g_ff_any` | :1564 | `gen_fn_decl`, `mem_ff_slot` |  |
| `g_ff_gen` | :1563 | `gen_fn_decl` |  |
| `g_ff_mark` | :1572 | `mem_emit_gated_drop` |  |
| `g_ffi_host_imports` | :1517 | `__target_arch` | g_ffi_host_imports is 1 when `--ffi-host-imports` is passed: external `&`-FFI libraries are then satisfied by  |
| `g_ffx_n` | :1573 | `__ffx_expand` |  |
| `g_fn_arcseen` | :1934 | `gen_fn_decl`, `mem_arg_consumption` |  |
| `g_fn_compiled` | :1887 | `__target_arch` | Names of functions whose body has been compiled — the "is the inline summary trustworthy for this callee?" tes |
| `g_fn_drops` | :2997 | `__target_arch` |  |
| `g_fn_escapes` | :1782 | `__target_arch` | Per-function escaping-parameter map. `g_fn_escapes[fname]` is the space-separated list of 0-based indices of p |
| `g_fn_handkeeps` | :1763 | `__target_arch` | The kept parameters whose value this function keeps ONLY in a struct the program manages by hand through a poi |
| `g_fn_inout` | :1642 | `__target_arch` | Per-function inout-parameter map. `g_fn_inout[fname]` is the space-separated list of 0-based indices of `inout |
| `g_fn_invoke_only` | :1809 | `__target_arch` | Per-function *invoke-only* parameter map (closure-env reclamation, docs/MEMORY.md §7.4). `g_fn_invoke_only[fna |
| `g_fn_keeps` | :1660 | `__target_arch` | Per-function KEPT-parameter map (docs/MEMORY.md §7.6): indices of parameters whose value the body stores somew |
| `g_fn_link_exports` | :1375 | `__target_arch` |  |
| `g_fn_link_sources` | :1374 | `__target_arch` | Source identities stay unmangled in semantic tables and diagnostics. Only their LLVM linkage names enter the p |
| `g_fn_mutates` | :1922 | `__target_arch` | Per-function container-mutation summary (docs/MEMORY.md §2.5). `g_fn_mutates[fname]` lists the 0-based paramet |
| `g_fn_mutates_witness` | :1923 | `__csv_has`, `gen_fn_decl`, `mem_arg_consumption` |  |
| `g_fn_noreturn` | :2001 | `__target_arch` | Noreturn registry. `g_fn_noreturn[fname]` is `1` when a call to fname never returns to its caller. Seeded with |
| `g_fn_pos_syms` | :1370 | `__target_arch` |  |
| `g_fn_reallocs` | :1972 | `__target_arch` | `g_fn_reallocs[fname]`: the parameters whose BUFFER the function may move or release (a reallocation, a free)  |
| `g_fn_reallocs_witness` | :1973 | `__csv_has`, `gen_fn_decl` |  |
| `g_fn_replaces` | :1983 | `__target_arch` | `g_fn_replaces[fname]`: the `inout` parameters an owned field of which (or the whole value) the function may r |
| `g_fn_replaces_witness` | :1984 | `__csv_has`, `emit_rawdrop_thunk`, `gen_fn_decl` |  |
| `g_fn_ret_alias` | :1913 | `__target_arch` | Per-function returned-HANDLE map — the ownership dual of g_fn_ret_param, and deliberately a separate map rathe |
| `g_fn_ret_count` | :2006 | `gen_fn_decl`, `mem_note_ret_clo_cap` | Count of `^` statements seen while compiling the current function body (closure bodies included — that over-co |
| `g_fn_ret_param` | :1899 | `__target_arch` | Per-function returned-parameter map. `g_fn_ret_param[fname]` is the space-separated list of 0-based indices of |
| `g_fn_ret_view` | :1795 | `__target_arch` | Per-function RETURNS-A-VIEW map. `g_fn_ret_view[fname]` is set when the body builds an aggregate one of whose  |
| `g_fn_safe` | :2998 | `__target_arch` |  |
| `g_fn_safe_list` | :2999 | `gen_fn_decl` |  |
| `g_fn_sink` | :1650 | `__target_arch` | Per-function sink-parameter map: space-separated parameter indices from explicit signatures and consuming call |
| `g_fn_slice_decls` | :1324 | `gen_fn_decl`, `mem_slice_decl_add` | Cheap per-function gate for the Phase 2D slice machinery: most functions declare no owned slices at all, and t |
| `g_fn_stores` | :1756 | `__target_arch` | The kept parameters whose value ends up somewhere the compiler drops — a literal, a local struct, a container  |
| `g_fn_strp` | :172 | `__own_sink_str_params` |  |
| `g_fn_unverified` | :1767 | `__target_arch` | Retention through an unverified foreign or indirect call. Lifetime-only facts; kept separate from diagnostic e |
| `g_fold_cap` | :64785 | `__fold_kind` |  |
| `g_fold_end` | :64798 | `__ext_calls_back`, `__fold_reg` |  |
| `g_fold_fcap` | :64791 | `__fold_jrnl_tok` |  |
| `g_fold_flags` | :64778 | `__sp_parts` | ── Late flag folding ────────────────────────────────────────────  Whether a callee takes a parameter over (si |
| `g_fold_flist` | :64789 | `__fold_jrnl_tok` |  |
| `g_fold_fn_end` | :64799 | `__fold_arg_false` |  |
| `g_fold_jcap` | :64797 | `__fold_kind` |  |
| `g_fold_jlist` | :64795 | `__fold_kind` | The flags a journal registration reads (nurl_journal_push_drop2), this round: a call made while one is registe |
| `g_fold_k` | :64800 | `__fold_operand` |  |
| `g_fold_map` | :64784 | `__fold_kind` | Six words per register: 0 kind (0 none, 1 i1 constant, 2 text alias), 1-2 the constant or the alias's byte ran |
| `g_fold_nf` | :64790 | `__fold_arg_false`, `__fold_jrnl_tok`, `__fold_kind` |  |
| `g_fold_nj` | :64796 | `__fold_arg_false`, `__fold_kind` |  |
| `g_fold_nt` | :64787 | `__fold_kind` |  |
| `g_fold_tcap` | :64788 | `__fold_kind` |  |
| `g_fold_touched` | :64786 | `__fold_kind` |  |
| `g_fold_x` | :64801 | `__fold_jrnl_regs`, `__fold_last_arg`, `__fold_operand`, `__fold_store_flag` |  |
| `g_fold_y` | :64802 | `__fold_last_arg`, `__fold_operand`, `__fold_store_flag` |  |
| `g_frozen_impls` | :1931 | `__coherence_register` | Whether the program declares any `% Frozen` impl (gen_call asks only then). |
| `g_frz_memo` | :1933 | `__lty_frozen` | __ty_lend_frozen's answers, per lowered type (`0` / `1` / `2`). |
| `g_frzp_any` | :1929 | `__arcp_note` | Whether any callee takes a `% Frozen` handle (`frzp##`): what it lends is frozen as an Arc's payload is, and r |
| `g_func_count` | :1499 | `__csv_has`, `__target_arch`, `gen_call_kwargs`, `store_closure_func` |  |
| `g_generic_struct_syms` | :1328 | `__target_arch` |  |
| `g_generic_syms` | :1327 | `__target_arch` |  |
| `g_hmemo_depth` | :52207 | `__is_owned_struct_ty` |  |
| `g_hmemo_log` | :52206 | `__is_owned_struct_ty` | ── Coinductive memo for the handle predicates ─────────────────────  `__is_owned_struct_ty` and `__clone_suppo |
| `g_impl_name_syms` | :1333 | `__target_arch` |  |
| `g_impl_pos_syms` | :1399 | `__target_arch` | `@ fname` scan registration. Two files are free to each have a private `__get`-style helper IN THEIR OWN HEADS |
| `g_impl_ret_syms` | :1332 | `__target_arch` |  |
| `g_impl_trait_syms` | :1334 | `__target_arch` |  |
| `g_impl_unsafe` | :2869 | `__coherence_register`, `scan_fn_sigs` | 1 while scan_impl_decl reads an impl written `unsafe % Trait Type { }`. |
| `g_import_roots` | :2031 | `collect_alias_targets` | The directories an import may resolve into (--import-root=DIR, repeatable, else NURL_IMPORT_ROOTS=DIR:DIR…), c |
| `g_in_cap` | :9992 | `__sym_hash_n` |  |
| `g_in_chunk` | :9994 | `__sym_hash_n` |  |
| `g_in_end` | :9996 | `__sym_hash_n` |  |
| `g_in_match_arm` | :1314 | `emit_or_chain` | Non-zero while parsing a `??` match-arm body. The XOR-confusion warning in gen_ret keys off "a non-terminator  |
| `g_in_n` | :9993 | `__sym_hash_n` |  |
| `g_in_pos` | :9995 | `__sym_hash_n` |  |
| `g_in_tab` | :9991 | `__sym_hash_n` | ── Interned strings ────────────────────────────────────────────── Every key and every plain value the symbol  |
| `g_in_unsafe` | :2872 | `gen_fn_decl` | 1 while the body of an `unsafe` function (or of a closure inside one) is being compiled. |
| `g_init_globals` | :1297 | `const_eval_int` | Globals set once at program start (`: ( Locked T ) g ( make )`), as `<name> <function> <type>;` triples: the e |
| `g_init_terminated` | :3147 | `__names_type` | g_init_terminated — 1 while a `:` binding's own INITIALISER terminated the block and the statement's remaining |
| `g_inl_wrap` | :3075 | `__target_arch` | Inline-wanting functions that use no crypto primitive themselves, by emission order (emit_fn_ir): the candidat |
| `g_inl_wrap_n` | :3076 | `__target_arch`, `emit_fn_ir`, `flush_simd_deferred` |  |
| `g_input_key` | :64713 | `__target_arch` |  |
| `g_input_source` | :64712 | `__target_arch` | Borrowed aliases to main's live source/key bindings when --stdin supplies an overlay. Every source read (inclu |
| `g_inst_done` | :57932 | `flush_deferred_instantiations` | flush_deferred_instantiations: emit all queued generic instantiations. Re-reads count each iteration so transi |
| `g_inst_tmpl` | :2882 | `gen_import_decl` | The template a generic instance is being compiled from (its unsafe-ness). |
| `g_join_deep` | :2967 | `__assign_result_lent`, `emit_or_chain`, `mem_join_heads_stmt`, `mem_note_ret_clo_cap` | …and whether one of those arms lent what it bound there (a view, a field of one): the assignment copies the jo |
| `g_join_droot` | :2969 | `emit_or_chain`, `mem_join_heads_stmt` | (…and the binding that arm read: what a refusal names.) |
| `g_join_flends` | :2930 | `emit_or_chain`, `mem_join_heads_stmt`, `mem_note_ret_clo_cap` | Whether a lending arm of the last `?` / `??` lent a field of this frame's own value (`? c . p s ( mk )`, p a l |
| `g_join_lent` | :2964 | `emit_or_chain`, `mem_join_heads_stmt` | Did an arm of the join that last published its ownership (`__last_join_own__`) lend what it yields — the const |
| `g_join_rdepth` | :2959 | `__assign_result_lent`, `emit_or_chain`, `mem_join_heads_stmt`, `mem_note_ret_clo_cap` | The scope depth of the binding the next `?` / `??` hands its value to, when that binding is assigned (`= t ? … |
| `g_last_alloc_reg` | :1616 | `__assign_result_lent`, `__csv_has`, `__names_type`, `gen_fn_decl` +2 | The register a fresh allocation's address is in (nurl_alloc, nurl_zalloc, malloc, calloc, alloc, zalloc — thro |
| `g_last_alloc_size` | :1622 | `__csv_has`, `gen_fn_decl`, `is_ptr_ty`, `mem_arg_consumption` | …and its byte count, when that memory is not zeroed (nurl_alloc, nurl_malloc, malloc): a cast of it to a struc |
| `g_last_cast_direct` | :1284 | `__gen_cast_body` | 1 when the last cast cast a binding (gen_cast; gen_agg_lit reads it) |
| `g_last_closure_cs` | :1464 | `__csv_has` |  |
| `g_last_closure_nonsend` | :1447 | `__csv_has` | record per impl block, verified after scan_fn_sigs once every impl across the program (incl. imports) is regis |
| `g_last_type_ptr` | :9848 | `nurl_str_cmp` |  |
| `g_lazy` | :49073 | `nurlc_print_help` |  |
| `g_lazy_edges` | :49093 | `lazy_reach`, `nurlc_print_help` | The program's reference graph, collected while scan_fn_sigs walks every file (0 when lazy compilation cannot r |
| `g_lazy_force` | :49075 | `gen_fn_decl_or_lazy`, `gen_import_decl`, `verify_super_obligations` |  |
| `g_lazy_live` | :49095 | `lazy_reach` | The functions lazy_reach found reachable from the roots: compiled in place. |
| `g_lazy_queue` | :49077 | `gen_fn_decl_or_lazy` |  |
| `g_lazy_root` | :49074 | `nurlc_print_help` |  |
| `g_lazy_scan` | :49076 | `gen_fn_decl_or_lazy` |  |
| `g_lazy_trace` | :49078 | `nurlc_print_help` |  |
| `g_lib_kind_memo` | :2995 | `__target_arch` |  |
| `g_lint` | :3132 | `__target_arch` | Unused-symbol lint (opt-in via `--lint`). Default OFF so ordinary builds — and the compiler's own bootstrap, w |
| `g_lint_fpend` | :3138 | `lint_init` | g_lint_fpend — the redundant-free lint's pending release calls (see lint_free_cand). |
| `g_lint_gen` | :3139 | `lint_fn_begin` |  |
| `g_lint_reads` | :3135 | `lint_init` |  |
| `g_lint_recording` | :3154 | `nurlc_print_help` | 1 only during the main parse_program pass. Cleared before flush_deferred_instantiations so synthetic generic m |
| `g_lint_syms` | :3133 | `lint_init` |  |
| `g_lint_used` | :3134 | `lint_init` |  |
| `g_live_lexers` | :10201 | `__lx_is_space` |  |
| `g_live_symtables` | :10200 | `__sym_hash_n` |  |
| `g_lm_calls` | :1872 | `__gen_cast_body`, `mem_arg_consumption` | While an aggregate literal is built (g_lm_depth > 0): every bare identifier a call in it hands to its callee,  |
| `g_lm_depth` | :1874 | `__gen_cast_body` |  |
| `g_lm_inner` | :1873 | `__gen_cast_body` |  |
| `g_lm_pend` | :1875 | `__lm_moved_names` |  |
| `g_lm_pend_n` | :1881 | `__lm_moved_names` |  |
| `g_loop_break_used` | :2017 | `__target_arch` | `g_loop_break_used[serial]` is `1` when a `break` targeting the loop numbered `serial` (g_loop_serial, which n |
| `g_loop_nest` | :1571 | `gen_foreach`, `gen_loop` |  |
| `g_loop_serial` | :1714 | `gen_foreach`, `gen_loop` |  |
| `g_lsrc_imemo` | :2892 | `bck_defer_fn` | …and as bits per callee (mem_fn_lends_arg). |
| `g_lsrc_memo` | :2890 | `bck_defer_fn` | What each callee lends (mem_fn_lend_sources), once every summary is final: the deferred walks' memo, 0 outside |
| `g_match_ser` | :1570 | `emit_or_chain` |  |
| `g_max_nesting` | :143 | `__target_arch` | The limit, 0 for none: --max-nesting / NURL_MAX_NESTING, else 1000 (nurlc_print_help says so too). |
| `g_max_nesting_set` | :146 | `__target_arch` | Who set g_max_nesting: 0 the default or the variable, 1 a flag, 2 --max-nesting-fixed (then nothing changes it |
| `g_maybe_moved` | :1528 | `__target_arch` |  |
| `g_member_obj` | :1575 | `__gen_cast_body`, `mem_arg_consumption`, `store_global` |  |
| `g_member_path` | :2924 | `__gen_cast_body` |  |
| `g_member_path_on` | :2923 | `__assign_result_lent`, `__gen_cast_body`, `__names_type`, `gen_dyn_construct` +3 | The field path the last member read named (`. . s a h` → `s.a.h`; an element read through a pointer is the poi |
| `g_mono_tparam_tys` | :2084 | `gen_import_decl` | Space-separated list of the concrete type-arguments substituted for a generic function's type parameters in th |
| `g_mp` | :64825 | `__dce_ident_byte`, `__ext_calls_back` | ── Journal elision ───────────────────────────────────────────────── A temporary registered with the panic jou |
| `g_msealed` | :1586 | `__gen_cast_body` | The last field read (gen_member) was out of a sealed representation, at any depth of its chain, or out of a bi |
| `g_msealed_ty` | :1587 | `__gen_cast_body` |  |
| `g_nc_flag_caps` | :1681 | `__csv_has` | The captures of the closure being built that cannot be copied, owned by a binding of the enclosing frame, in a |
| `g_nc_own_caps` | :1686 | `__csv_has` | …and those of a closure returned from the frame: the env owns them under a flag of its own, which the body cle |
| `g_ncl_n` | :2938 | `__nc_bind_lend_note`, `gen_fn_decl` | How many bindings of the function being compiled hold a value that cannot be copied which a call may lend (`__ |
| `g_nest_abort` | :149 | `__nest_die` | 1 once a program passed the nesting limit: every parse_program walk stops at the declaration it is in, without |
| `g_nest_depth` | :140 | `__ice_report`, `__nest_enter`, `gen_expr`, `gen_stmt` +1 | The nesting limit (see `── Nesting limit` above gen_expr): the gen_expr / gen_stmt / parse_type levels open no |
| `g_nl_buf` | :47292 | `collect_fn_body` | N newlines — the re-lex padding that maps a template buffer's line 1 onto the template's real source line (see |
| `g_noaddr_visiting` | :1562 | `__ty_no_address_enum` |  |
| `g_open_bind_col` | :1723 | `__names_type` |  |
| `g_open_bind_line` | :1722 | `__names_type` |  |
| `g_open_bind_name` | :1721 | `__names_type` | The binding whose initialiser is being generated (name, and where its `:` statement starts), "" outside one. A |
| `g_origin_functions` | :44820 | `__target_arch` |  |
| `g_origin_named` | :44818 | `bck_record_inferred_escape`, `origin_expr` |  |
| `g_origin_nodes` | :44817 | `bck_record_inferred_escape`, `origin_expr` | Return-escape inference (docs/MEMORY.md §2.8): record that the enclosing function may RETURN this bare-identif |
| `g_origin_returns` | :44821 | `__target_arch` |  |
| `g_origin_work` | :44819 | `bck_record_inferred_escape`, `origin_expr` |  |
| `g_owned_globals` | :1292 | `const_eval_int` | Names of the mutable string globals that own their buffer (each has a compiler-emitted `<name>__nurlown` flag) |
| `g_part_n` | :2946 | `__mem_udrop_bind_flag`, `gen_fn_decl` | How many bindings of the function being compiled are cursors over part of a value (`__alias_part`) or may hold |
| `g_pending_escape` | :1835 | `__target_arch` | Deferred interprocedural-escape checks (docs/MEMORY.md §3 forward / generic boundary). A stack reference passe |
| `g_pending_impl` | :1857 | `__target_arch` | Deferred summary IMPLICATIONS (docs/MEMORY.md §2.7 / §2.8). A summary is inferred as each body compiles, so a  |
| `g_pending_inline` | :2787 | `gen_fn_decl`, `parse_toplevel_decl`, `scan_fn_sigs` | g_pending_inline is the `inline` prefix's counterpart to g_pending_simd: set when the parser consumes a TT_INL |
| `g_pending_pub` | :2776 | `parse_toplevel_decl`, `scan_fn_sigs`, `vis_take_pending_pub` | Visibility (grammar v2.0). Tracks the source-file of every @-defined function and per-file strict-mode opt-in. |
| `g_pending_raw` | :2796 | `scan_fn_sigs` |  |
| `g_pending_rawrep` | :2800 | `gen_struct_decl`, `parse_toplevel_decl` | `raw : Name { … }`: the struct's fields carry an invariant its API keeps (a device address that must stay insi |
| `g_pending_simd` | :2782 | `gen_fn_decl`, `parse_toplevel_decl`, `scan_fn_sigs` | g_pending_simd is the `simd` prefix's counterpart to g_pending_pub: set when the parser consumes a TT_SIMD ahe |
| `g_pending_unsafe` | :2789 | `gen_ffi_decl`, `gen_fn_decl`, `parse_toplevel_decl`, `scan_fn_sigs` | The `unsafe` prefix parsed ahead of the next declaration. |
| `g_pkgver_memo` | :11221 | `__lx_is_space` | ── `( pkg_version )` ───────────────────────────────────────────  `( pkg_version )` is the `version` of the pa |
| `g_priv_file_count` | :1366 | `priv_file_id` |  |
| `g_priv_file_ids` | :1365 | `__target_arch` | `??`/`?` arms). Consumers that NEED a value (a cast, a let/assign) die with this appended, so "produced no val |
| `g_priv_owner_files` | :1368 | `__target_arch` |  |
| `g_priv_owner_ids` | :1367 | `__target_arch` |  |
| `g_priv_warned` | :1369 | `__target_arch` |  |
| `g_pt_star` | :792 | `parse_type_paren`, `parse_type_ptr` | Raw-pointer types parse_type has read (`*T` anywhere but inside a closure type): a struct field whose type mov |
| `g_ptr_own_n` | :1574 | `__ptr_own_set`, `gen_fn_decl` |  |
| `g_ptrtab` | :1549 | `__target_arch` |  |
| `g_raw_fns` | :2795 | `scan_fn_sigs` | `raw @ f …` (grammar v2.9): f's body may use raw memory, as an `unsafe` one's may, and f's CALLER must vouch f |
| `g_rawlit_n` | :1577 | `gen_fn_decl`, `mem_note_rawlit` |  |
| `g_rawlit_pending` | :1576 | `__gen_cast_body`, `gen_fn_decl`, `mem_note_rawlit`, `mem_rawlit_unclaimed` |  |
| `g_rawret_memo` | :26409 | `__fn_raw_ret` |  |
| `g_repl_edges` | :1985 | `__dyn_virtual_round`, `mem_arg_consumption` |  |
| `g_res_type_syms` | :558 | `__target_arch` | ── Res-type NURL tracking (must be declared before parse_type_res) ── g_res_type_syms is initialized to a new  |
| `g_ret_forbidden` | :1308 | `__gen_stmt_level`, `gen_logical_or_bitwise_and`, `gen_logical_or_bitwise_or`, `gen_operand` +1 | Cascade guard: 1 while parsing a VALUE OPERAND (a binary/unary/cast/ member operand, a call argument, a `?`/`? |
| `g_retcap_n` | :1579 | `gen_fn_decl` |  |
| `g_retclo_n` | :1578 | `gen_fn_decl` |  |
| `g_root_syms` | :1664 | `__target_arch` | The module's root symbol table, for the type questions asked where no table is at hand (__is_handle_ty on a st |
| `g_rpg_cur` | :26681 | `bck_owning_reads` |  |
| `g_rpg_cur_id` | :26682 | `bck_owning_reads` |  |
| `g_rpg_cur_pfx` | :26683 | `bck_owning_reads` |  |
| `g_rpg_ecap` | :26698 | `resolve_pending_ret_escapes` |  |
| `g_rpg_edge` | :26696 | `resolve_pending_ret_escapes` |  |
| `g_rpg_f` | :26693 | `bck_owning_reads` | A function's row, RPG_FW words: 0 its name (a copy), 1 1 when it has records, 2 what its other summaries say i |
| `g_rpg_fcap` | :26695 | `bck_owning_reads` |  |
| `g_rpg_fid` | :26684 | `bck_owning_reads` |  |
| `g_rpg_list` | :46210 | `__raw_writer` | The records of function `f`, in order: g_rpg_list[ row 11 .. next ). |
| `g_rpg_me_id` | :26700 | `gen_fn_decl`, `resolve_pending_ret_escapes` |  |
| `g_rpg_me_self` | :26699 | `gen_fn_decl` |  |
| `g_rpg_names` | :26680 | `bck_owning_reads` |  |
| `g_rpg_nedge` | :26697 | `resolve_pending_ret_escapes` |  |
| `g_rpg_nfn` | :26694 | `bck_owning_reads` |  |
| `g_rpg_nrec` | :26673 | `bck_owning_reads` |  |
| `g_rpg_nslot` | :26678 | `bck_owning_reads` |  |
| `g_rpg_on` | :2880 | `gen_fn_decl` | …and its graph is recorded (g_rpg): raw code with a parameter that can hold storage. Without one, nothing the  |
| `g_rpg_rcap` | :26674 | `bck_owning_reads` |  |
| `g_rpg_rec` | :26672 | `bck_owning_reads` |  |
| `g_rpg_scap` | :26679 | `bck_owning_reads` |  |
| `g_rpg_sname` | :26677 | `bck_owning_reads` |  |
| `g_rpg_tmp` | :26939 | `__rprov_lend_expr` | A returned pointer (or a returned literal's pointer field) whose expression read `reads`: bound to a name of i |
| `g_rpg_u` | :26676 | `bck_owning_reads` |  |
| `g_rpg_v` | :26675 | `bck_owning_reads` |  |
| `g_rprov_on` | :2876 | `gen_fn_decl` | Raw provenance is followed in this body (__rprov_note): it is raw code, an `unsafe` function or the trusted st |
| `g_sanitize_address` | :64705 | `__target_arch` | Emission policy, set by main's --sanitize-address flag. |
| `g_sealed_views` | :1582 | `__sealed_view_bind` |  |
| `g_sh_pend` | :1879 | `mem_arg_consumption` | A sealed representation's field handed to a function of the program not compiled yet: whether it changes that  |
| `g_sh_pend_n` | :1880 | `mem_arg_consumption` |  |
| `g_simd_defer` | :3063 | `__target_arch` | `simd` functions held back until the module is complete (defer_multiversion): `<k>.ir` / `.n` / `.r` / `.p` →  |
| `g_simd_defer_n` | :3064 | `__target_arch`, `defer_multiversion`, `flush_simd_deferred` |  |
| `g_simd_fns` | :3055 | `__crypto_fn_ir` | Every `simd` function emit_multiversion has written, by its IR name (`__nurl_fn.f`), space-separated. The spli |
| `g_sound` | :28288 | `bck_sound` | The sound-and-complete rules (docs/SOUND_COMPLETE_PLAN.md): moves and borrows. Under development they run when |
| `g_source_snapshots` | :64714 | `__dce_ident_byte`, `__target_arch` |  |
| `g_sp_buf` | :47277 | `collect_fn_body` | The spaces that put the first token of a re-lexed template line at its SOURCE column. Tokens are joined by sin |
| `g_sp_pin` | :67194 | `__sp_whole` |  |
| `g_sp_pq` | :67195 | `__sp_whole` |  |
| `g_sp_pqn` | :67196 | `__sp_whole` |  |
| `g_sp_rchg` | :64551 | `__sp_whole` |  |
| `g_split_fh` | :64569 | `__sp_emit_global` |  |
| `g_split_fill` | :64547 | `__sp_whole` |  |
| `g_split_max` | :64541 | `__target_arch` |  |
| `g_split_min` | :64542 | `__target_arch` |  |
| `g_split_n` | :64540 | `__sp_parts`, `__sp_whole` | Partitioned emission — see "Partitioned emission" below. |
| `g_split_name` | :64544 | `__sp_emit_global` |  |
| `g_split_out` | :64543 | `__target_arch` |  |
| `g_split_part` | :64546 | `__sp_whole` |  |
| `g_split_priv` | :64548 | `__sp_whole` |  |
| `g_split_rep` | :64549 | `__sp_whole` |  |
| `g_split_repmask` | :64550 | `__sp_whole` |  |
| `g_srcx_on` | :2987 | `gen_fn_decl` | Source expressions (srcx): where a view's value came from, as an expression the walk evaluates once every summ |
| `g_stmt_bare_lit` | :5825 | `__gen_stmt_level` | g_stmt_bare_lit — set by gen_stmt to 1 when the statement it just parsed was a bare numeric/string LITERAL in  |
| `g_stmt_bare_value` | :5852 | `__gen_stmt_level` | g_stmt_bare_value — the literal flag's general sibling (critic A2, the last silent prefix-arity cascade): set  |
| `g_stmt_col` | :5662 | `__gen_stmt_level`, `gen_block_ret` | g_stmt_col — column of the current statement's first token, captured alongside g_stmt_line. `die_stmt` anchors |
| `g_stmt_lex` | :5668 | `__gen_stmt_level`, `__lx_is_space` | g_stmt_lex — the lexer that statement came from, so a check deep in codegen that has no lexer of its own (__nc |
| `g_stmt_line` | :5655 | `__gen_stmt_level`, `gen_block_ret` | g_stmt_line — source line of the statement gen_stmt is currently parsing. Read by gen_ident's "unexpected toke |
| `g_str_idx` | :1280 | `emit_deferred_cstr`, `emit_str_global`, `gen_str_lit` |  |
| `g_str_syms` | :1281 | `__target_arch` |  |
| `g_strict_arity` | :1539 | `__target_arch` | strict-arity: the n-ary `&`/`\|` arity trap is an ERROR by default. The trap is the language's one documented f |
| `g_strict_borrowck` | :1527 | `__target_arch` | `--strict-borrowck` (off by default) enables three additional checks: (1) aliased mutation through `. obj fiel |
| `g_struct_inst_syms` | :1331 | `__target_arch` | <sname>__stparams → space-separated type-var names (e.g. "T" or "K V") <sname>__sbody    → raw body source inc |
| `g_struct_ll` | :3081 | `__target_arch` | Every struct's LLVM field types, by IR name (`%` dropped), as its body lists them: what __ty_has_wide asks whe |
| `g_struct_tmp` | :1823 | `__csv_has`, `gen_fn_decl`, `mem_arg_consumption`, `mem_clo_drop_discarded` | The struct temporary with owned fields most recently returned by a call, as `<value> <%Type> <owned-field toke |
| `g_summaries_final` | :1565 | `mem_emit_arg_flags` |  |
| `g_super_obligations` | :1437 | `__coherence_register` |  |
| `g_sx` | :3032 | `__sx_enter` |  |
| `g_sx_at` | :3031 | `__sx_enter` |  |
| `g_sx_n` | :3030 | `__sx_enter` |  |
| `g_sxe_arc` | :1940 | `bck_arc_frozen_check`, `bck_borrow_begin`, `bck_sx_handle_mark`, `bck_sx_name` +2 | At the borrow walk: whether the value of the source expression being evaluated is a view of an Arc's payload — |
| `g_sxe_pos` | :29604 | `__src_mark`, `bck_sx_arg_sources`, `bck_sx_handle_mark`, `bck_sx_sources` | ── Source expressions in the walk ── The cursor of the evaluation in progress (bck_sx_sources), and whether it |
| `g_tf_body` | :66502 | `__ir_write_range` |  |
| `g_tf_en` | :66501 | `__ir_write_range` |  |
| `g_tf_map` | :66504 | `__ir_write_range` |  |
| `g_tf_olen` | :66506 | `__ir_write_range` |  |
| `g_tf_out` | :66505 | `__ir_write_range` |  |
| `g_tf_st` | :66500 | `__ir_write_range` | ── Type definitions first ──────────────────────────────────────────  A named struct is printed where the gene |
| `g_tf_state` | :66503 | `__ir_write_range` |  |
| `g_thv_precise` | :1580 | `bck_sx_handle_mark`, `gen_mem_dup` |  |
| `g_trait_pending` | :1420 | `__target_arch` | <Trait>__tparam           → trait's generic type-var name (e.g. "T") <Trait>__defaults         → space-separat |
| `g_trait_syms` | :1406 | `__target_arch` | first registration. A `$`-imported impl is scanned once per importer, so the SAME (method, type) is registered |
| `g_trust_memo` | :26289 | `__trust_root` | ── Raw memory and `unsafe` (docs/SOUND_COMPLETE_PLAN.md, P1) ───────  The stdlib is the vouched-for base: its  |
| `g_trust_roots` | :26290 | `__trust_root` |  |
| `g_type_count` | :1498 | `__target_arch`, `store_closure_type` |  |
| `g_type_emit_base` | :1501 | `__target_arch` |  |
| `g_type_layouts` | :1771 | `__target_arch` | Type layout metadata precedes cleanup decisions; IR definitions retain their source ordering. This table owns  |
| `g_udrop_noinit` | :1728 | `__gen_cast_body`, `__names_type`, `__sb`, `emit_or_chain` | Set by a `:` binding just before registering its value: the binding rule stores the drop flag itself, so regis |
| `g_udrop_tmpown` | :1748 | `__gen_cast_body`, `__sb`, `emit_or_chain` | Set by a call's temporary given an owner of its own (h233, h330) just before registering it: its journal regis |
| `g_unsafe_fns` | :2791 | `gen_dyn_construct`, `scan_fn_sigs` | The functions declared `unsafe` (name → 1; 0 until the first one). |
| `g_unsafe_list` | :2842 | `mem_velem_tag` |  |
| `g_unsafe_report` | :2841 | `__target_arch` |  |
| `g_use_argxfer` | :1668 | `mem_emit_string_arg_transfers`, `mem_sink_str_arg` |  |
| `g_use_clear_if` | :1667 | `mem_udrop_flag_clear_if` | Whether this module calls the drop-flag helpers (emitted at module end). |
| `g_use_hown` | :1669 | `emit_dyn_method_thunk`, `mem_capture_hown`, `mem_publish_hown` |  |
| `g_use_ownstr` | :174 | `mem_clo_ret_own_str`, `mem_note_ret_clo_cap` |  |
| `g_use_sinkstr` | :171 | `mem_sink_str_arg` |  |
| `g_user_drop_seen` | :185 | `__coherence_register`, `emit_dyn_drop_fn` | 1 once the program declares a `% Drop` impl of its own (scan_impl_decl): until then no type has one, and the q |
| `g_ut_gen` | :2898 | `bck_unsafe_ctx` |  |
| `g_vcall` | :3082 | `__target_arch` |  |
| `g_vcall_n` | :3083 | `__target_arch`, `__vcall_thunk` |  |
| `g_vcall_site` | :3084 | `__vcall_thunk` |  |
| `g_vctl_seen` | :2819 | `gen_fn_decl`, `mem_arg_consumption`, `mem_note_velem` | Set by a call to nurl_vctl_data; the let that binds its result marks the pointer `__velem` (its element access |
| `g_vis_file_gen` | :2897 | `vis_set_current_src_file` |  |
| `g_vis_inst_targs` | :2087 | `__ty_memo_forget` | The type arguments of the generic struct being instantiated (its field types are parsed in a pseudo-file); see |
| `g_vis_syms` | :2777 | `__target_arch` |  |
| `g_void_reason` | :1335 | `__void_reason_clear`, `emit_or_chain`, `int_width`, `mem_join_heads_stmt` |  |
| `g_wide_struct` | :3087 | `__note_struct_field` | Set once a struct field is itself a wide vector: from then on every function is looked at for indirect calls p |
| `g_xl_cap` | :3041 | `bck_xl_resolve` |  |
| `g_xl_depth` | :3037 | `bck_xl_declare`, `bck_xl_resolve` | The frame depth and renames of the lexical scopes the borrow walk's rows are translated in (bck_xl_declare_id) |
| `g_xl_nser` | :3042 | `bck_xl_declare`, `bck_xl_resolve` |  |
| `g_xl_op` | :3040 | `bck_xl_resolve` |  |
| `g_xl_ren` | :3038 | `bck_xl_resolve` |  |
| `g_xl_ss` | :3039 | `bck_xl_resolve` |  |

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
| `g_arg_ident_log` | :1183 | `gen_call`, `gen_ident` | --strict-borrowck only: every binding NAME read while generating the current call argument, including reads ne |
| `g_at` | :49680 | `__ext_compute` | ── Which functions run inside a recover extent ───────────────── |
| `g_auto_drop_strings` | :2353 | `main` | Phase 2B auto-drop-strings feature flag. Default ON. Compiler's own source uses patterns (strings stored via n |
| `g_bck` | :1307 | `main` |  |
| `g_bck_bind_scalar` | :21243 | `bck_record_binding` | Set by bck_record_binding for its row: 1 when the binding holds no heap value and no address (a scalar), so no |
| `g_bck_bind_sown` | :21251 | `bck_record_binding`, `gen_assign`, `gen_let_or_struct` | …and 1 when it is an `s` that owns the buffer it points at (field 5 `o`): a tracked owned string, every assign |
| `g_bck_bind_wview` | :21245 | `bck_record_binding` | …and 1 when that view owns nothing (field 5 `w`, bck_record_binding). |
| `g_bck_cap_names` | :1241 | `bck_add_cap_name`, `bck_fn_begin`, `gen_closure_expr` | Names of `:`-bound closures in the CURRENT function whose capture list is non-empty — the allocation-free pre- |
| `g_bck_cap_via` | :1252 | `bck_fn_begin`, `bck_note_closure_caps`, `gen_closure_expr`, `resolve_deferred_borrowck` | `<handle> <closure>` pairs for the current function: which closure binding made a captured handle reachable at |
| `g_bck_close` | :23643 | `bck_index_closes` | The close marker of every open marker, found once per walk with a stack per bracket kind: the walk asks for th |
| `g_bck_closure_depth` | :1344 | `gen_closure_expr` |  |
| `g_bck_depth` | :1310 | `bck_block_enter`, `bck_block_exit`, `bck_fn_begin`, `gen_closure_expr` | data (statement list etc.); allocated in main() only when --borrowck is set |
| `g_bck_dser` | :2503 | `bck_intern` |  |
| `g_bck_end_eonly` | :2447 | `bck_borrow_sweep` | Set while a borrow end comes from elements dropped or replaced (not the value itself): an owner holding a clos |
| `g_bck_errors` | :1348 | `__ptr_stale_warn`, `__ptr_stale_warn_at`, `bck_emit_error` | capture hooks no-op so closure statements do not inline into the enclosing function's list (so closure scopes  |
| `g_bck_gen` | :1328 | `bck_analyze` |  |
| `g_bck_has_borrow` | :22693 | `bck_analyze`, `bck_borrow_begin`, `bck_dep_add`, `bck_walk_seq` | Set once a function records a borrow: only then does the walk compare states row by row to end borrows whose s |
| `g_bck_has_deps` | :2443 | `bck_analyze`, `bck_dep_add` | Whether this function's walk has recorded any view dependency (bck_dep_add), and statement `vpass` rows pendin |
| `g_bck_has_paths` | :22695 | `bck_analyze`, `bck_intern` | Set once a function interns a field path (`s.items`, bck_intern). |
| `g_bck_inew` | :2504 | `bck_intern` |  |
| `g_bck_inn` | :1332 | `bck_analyze`, `bck_intern` | intern table — bumped per bck_analyze so entries from earlier functions read as misses without any table clear |
| `g_bck_nrows` | :22702 | `bck_explode`, `bck_row_put` |  |
| `g_bck_ownerless` | :1326 | `bck_flush_moves`, `bck_stash_store`, `bck_take_owner_stores` |  |
| `g_bck_pcap` | :22708 | `bck_intern` |  |
| `g_bck_pn` | :22707 | `bck_intern` |  |
| `g_bck_pr` | :22706 | `bck_intern` | Per id of the function analysed now: the binding it belongs to (itself unless a field path) and a path's spell |
| `g_bck_pvpass_n` | :2448 | `bck_flush_vpass`, `bck_side_lists_put`, `bck_side_lists_take`, `bck_stash_vpass` |  |
| `g_bck_rcap` | :22703 | `bck_row_put` |  |
| `g_bck_rec_off` | :1343 | (init only) | >0 while the borrow checker's capture hooks must not record. Used to be spelled `g_bck_closure_depth != 0`, wh |
| `g_bck_ret_dep` | :2489 | `gen_ret` |  |
| `g_bck_ret_sx` | :2488 | `gen_ret` | The source expression of a returned view (field 8 of its `ret` row), and 1 when it is an owner returned by nam |
| `g_bck_rhs_callee` | :21257 | `gen_assign`, `gen_let_or_struct` | The call a `let` / `assign` binds the result of (field 6 of its row): a lend the walk learns from the callee's |
| `g_bck_rhs_lend` | :21483 | `gen_assign`, `gen_let_or_struct` | Set by a binding whose right-hand side is a call: the sources a borrow of its result has (bck_call_lend_srcs); |
| `g_bck_rhs_sx` | :21260 | `gen_assign`, `gen_let_or_struct` | The source expression of a `let` / `assign`'s right-hand side (field 8 of a view's row, g_srcx_on): its source |
| `g_bck_rk` | :22701 | `bck_row_put` | …and each row's kind code (bck_kind_code). |
| `g_bck_rlen` | :22699 | `bck_row_put` |  |
| `g_bck_rows` | :22698 | `bck_row_put` | The rows of the function being walked (bck_explode / bck_rec): copies and their lengths. |
| `g_bck_sc` | :2509 | `bck_scope_push` |  |
| `g_bck_sc_cap` | :2508 | `bck_scope_push` |  |
| `g_bck_sc_n` | :2507 | `bck_scope_push`, `bck_walk_seq` | The blocks the walk is in, innermost last (bck_scope_push): rows [lo, hi) of each, and whether it is a loop's  |
| `g_bck_sx_gen` | :1327 | `bck_walk_seq` |  |
| `g_bck_view_reads` | :21253 | `bck_record_binding` | What a view binding's right-hand side read (bck_record_binding). |
| `g_bcls_memo` | :2437 | `main` | A binding class per LLVM type (bck_bind_class), and the trusted-file answer for the current source file (bck_u |
| `g_blk_tail_lit_col` | :4973 | `gen_block_expr`, `gen_block_ret` |  |
| `g_blk_tail_lit_line` | :4972 | `gen_block_expr`, `gen_block_ret`, `gen_block_stmts`, `gen_cond` +1 | g_blk_tail_lit_line/col — the dangling-literal exemption's escape hatch, closed. A bare literal as a value blo |
| `g_body_ends` | :9497 | `body_ends_reset` | Where each brace block ends: "<text identity> <offset of a '{'>" → the offset just past its matching '}'. Ever |
| `g_borrowck` | :1267 | `main` | ── Borrow-checker state ───────────────────────────────────────── g_borrowck is 1 (ON) by default; `--no-borro |
| `g_call_lend_roots` | :2428 | `gen_call` |  |
| `g_call_roots` | :2427 | `gen_call` | The call just generated, when one of its arguments was a field path (`. b items`): its arguments with that fie |
| `g_clo_bind_name` | :1410 | `gen_closure_expr`, `gen_let_or_struct` |  |
| `g_clo_caps_now` | :2484 | `gen_closure_expr` | While a closure body is compiled: what it captured (g_clo_caps_now) and the calls it hands one of them — or a  |
| `g_clo_detach` | :1408 | `gen_call`, `gen_closure_expr` | Set by a call compiling a closure literal as the closure a thread or a fiber runs, or by a `:` binding of one  |
| `g_clo_detach_shared` | :1402 | `__clo_detach_moves`, `gen_closure_expr` | The detached closure's captures taken by share (__clo_detach_moves); consumed by gen_closure_expr like the mov |
| `g_clo_lend_set` | :1325 | `gen_call` |  |
| `g_clo_tmp` | :1484 | `__clo_tmp_set` | The owned closure temporary most recently produced, as `<value> <env>` (docs/MEMORY.md §7.4): published by a c |
| `g_clolend_n` | :1324 | `mem_note_clo_lend` |  |
| `g_closure_consumed` | :1231 | `bck_stash_move`, `gen_closure_expr` | Names a closure BODY consumed. bck_stash_move drops its records while inside a closure — the body's statements |
| `g_closure_defs` | :1253 | `main` |  |
| `g_closure_effects` | :2485 | `__clo_effect_note`, `gen_closure_expr` |  |
| `g_closure_emit_base` | :1257 | `emit_closure_globals`, `main` |  |
| `g_closure_types` | :1254 | `main` |  |
| `g_cond_depth` | :1305 | `gen_cond`, `gen_loop` | Nesting depth of "we are parsing an enclosing construct's CONDITION". The arity check above fires when a `{` f |
| `g_coverage_link_ir` | :1623 | `main` |  |
| `g_coverage_meta_id` | :1624 | `dbg_flush` |  |
| `g_coverage_notes` | :1622 | `main` |  |
| `g_coverage_prefix` | :1621 | `main` |  |
| `g_cpu_dispatch` | :2526 | `main` | Which wider ISA the `simd` prefix dispatches to. 1 = x86-64-v3 (AVX2 + BMI2 + FMA), 0 = no dispatch, emit the  |
| `g_cur_params` | :2480 | `gen_fn_decl_concrete` |  |
| `g_cur_ret_llty` | :140 | `gen_fn_decl_concrete` | LLVM return type of the function whose body is currently being generated. Diagnostics-only: gen_field_store co |
| `g_dbg_blob_syms` | :1627 | `dbg_init` | module-flag id we might add later |
| `g_dbg_cu_id` | :1630 | `dbg_init` |  |
| `g_dbg_current_file_id` | :1659 | `gen_fn_decl_concrete` | defining path for the mono being emitted (the mono's lexer filename is the synthetic `<generic …>`). Set/resto |
| `g_dbg_current_loc` | :1633 | `dbg_synth_begin`, `dbg_synth_end`, `emit_dbg_line_eol`, `gen_block_expr` +5 | (0 outside any function) |
| `g_dbg_current_subprogram` | :1631 | `dbg_synth_begin`, `dbg_synth_end`, `gen_closure_expr`, `gen_fn_decl_concrete` |  |
| `g_dbg_enabled` | :1620 | `main` | ── DWARF debug-info state ─────────────────────────────────────── All zero/empty when --g is OFF; emit helpers |
| `g_dbg_file_id` | :1629 | `dbg_init` | flushed at end-of-module by dbg_flush |
| `g_dbg_file_syms` | :1648 | `dbg_init` | uses this instead of `nurl_lex_line` for the !DISubprogram source line. Set by emit_one_instantiation so per-m |
| `g_dbg_next_id` | :1625 | `dbg_alloc_id` |  |
| `g_dbg_override_file` | :1653 | `__lazy_emit`, `emit_one_instantiation` | every source file gets its own !DIFile and a subprogram debug-attributes to the file that DEFINES it (imports, |
| `g_dbg_override_line` | :1642 | `__lazy_emit`, `emit_one_instantiation` | the type for every local until Phase 6 lays down per-LLVM-type DIBasicType entries indexed by `vt`. |
| `g_dbg_placeholder_ty` | :1638 | `dbg_init` | dbg_init and reused for every fn. Phase 6 will replace with per-fn signature types. |
| `g_dbg_subroutine_ty` | :1635 | `dbg_init` | emit_dbg_eol then omits `, !dbg !N`) |
| `g_dbg_type_syms` | :1686 | `dbg_init` |  |
| `g_dce` | :49221 | `main` |  |
| `g_dce_at` | :49268 | `dce_emit_module`, `dce_free` |  |
| `g_dce_end` | :49264 | `dce_emit_module`, `dce_free` |  |
| `g_dce_keep` | :49232 | `main` | `--keep=a,b,c` — extra DCE roots.  The pass's root set is `main` plus whatever module-scope constants name. Th |
| `g_dce_live` | :49265 | `dce_emit_module`, `dce_free` |  |
| `g_dce_map` | :49269 | `dce_emit_module`, `dce_free` |  |
| `g_dce_mod` | :49262 | `dce_emit_module` | The module text, as an integer cast of a BORROWED `s`. Deliberately not a `: ~ s` global: a mutable string glo |
| `g_dce_qn` | :49267 | `__dce_mark_name`, `dce_emit_module` |  |
| `g_dce_queue` | :49266 | `dce_emit_module`, `dce_free` |  |
| `g_dce_start` | :49263 | `dce_emit_module`, `dce_free` |  |
| `g_dead_payload` | :29271 | `gen_agg_lit`, `gen_cast` | Set while the payload of a None literal is generated, when that payload is a cast (gen_agg_lit): the one cast  |
| `g_defer_count` | :1047 | `gen_defer`, `gen_fn_decl_concrete` |  |
| `g_deferred_bck` | :1529 | `main` | Functions whose borrow-check walk is parked until the whole module has compiled (see borrowck_fn_end). `n` is  |
| `g_diag_ctx` | :131 | `__impl_sig_check`, `dyn_subst_parts`, `emit_missing_defaults`, `emit_one_instantiation` +2 | Diagnostic context suffix, appended to every die/warn message while non-empty. Set (and saved/restored — insta |
| `g_diag_recover_active` | :122 | `main`, `parse_program` |  |
| `g_did_ret` | :1012 | `__close_dead_block`, `__handle_unreachable_stmt`, `__tail_noreturn_close`, `gen_closure_expr` +9 |  |
| `g_drop_base` | :2474 | `main` | Which parameters each safe function may drop or replace the elements of (bck_callee_drops_elems): witnessed wh |
| `g_drop_edges` | :2476 | `main` |  |
| `g_drop_glue_ty` | :144 | `gen_trait_or_impl` | The LLVM type of the value a `% Drop` impl's `drop` is being compiled for (`%R`), or `` — while set, every exi |
| `g_dyn_dtout` | :1157 | `dyn_method_decltrait` | dyn_method_decltrait's result rides a global too: its callers sit ABOVE its definition, so an owned return wou |
| `g_dyn_flat_out` | :1151 | `__dyn_flat_add`, `__dyn_flat_reset` | Scratch accumulators for dyn_flat_methods (a NURL fn returns one value, so the recursive supertrait walk threa |
| `g_dyn_flat_seen` | :1152 | `__dyn_flat_add`, `__dyn_flat_reset` |  |
| `g_dyn_needed` | :1148 | `dyn_note_needed` | Dynamic trait objects (`%Trait`, docs/spec.md §4.9). Space-separated set of trait names that appear as a `%Tra |
| `g_env_moved` | :1399 | `gen_closure_expr` | …and, for one that a thread or a fiber will run, the captures it takes over from bindings the function no long |
| `g_env_owns_handles` | :1393 | `gen_closure_expr` | Set around a returned closure literal's env generation: its String / Vec / owning-struct captures move into (a |
| `g_env_released` | :1396 | `gen_closure_expr` | …and, for a closure that releases some captures itself, which (their env field is not dropped again). |
| `g_env_shared` | :1404 | `gen_closure_expr` | …and the same set while that closure's env is built and described. |
| `g_err_count` | :121 | `__diag_abort` | Multi-error mode (rustc-style): while parse_program's per-declaration recovery frame is active (g_diag_recover |
| `g_ext` | :49677 | `__ext_compute`, `__jrnl_elide` |  |
| `g_ext_glob` | :49685 | `__ext_compute` |  |
| `g_ext_mlen` | :49686 | `__ext_compute` |  |
| `g_ext_q` | :49681 | `__ext_compute` |  |
| `g_ext_qn` | :49682 | `__ext_compute`, `__ext_mark` |  |
| `g_ext_sig` | :49684 | `__ext_by_sig`, `__ext_compute` |  |
| `g_ff_any` | :1313 | `gen_fn_decl_concrete`, `mem_ff_slot` |  |
| `g_ff_gen` | :1312 | `gen_fn_decl_concrete` |  |
| `g_ff_mark` | :1317 | `mem_emit_gated_drop` |  |
| `g_ffi_host_imports` | :1274 | `main` | g_ffi_host_imports is 1 when `--ffi-host-imports` is passed: external `&`-FFI libraries are then satisfied by  |
| `g_ffx_n` | :1318 | `__ffx_expand` |  |
| `g_fn_arc_mut` | :1570 | `main` | Per-function shared-mutation summary (docs/MEMORY.md §6.5). `g_fn_arc_mut[fname]` is `1` when the body mutates |
| `g_fn_arc_mut_witness` | :1204 | `gen_call`, `gen_closure_expr`, `gen_fn_decl_concrete` | Function-level witness for the same property. NOT a symbol-table key: the mutation is usually inside a loop or |
| `g_fn_compiled` | :1535 | `main` | Names of functions whose body has been compiled — the "is the inline summary trustworthy for this callee?" tes |
| `g_fn_drops` | :2477 | `main` |  |
| `g_fn_escapes` | :1448 | `main` | Per-function escaping-parameter map. `g_fn_escapes[fname]` is the space-separated list of 0-based indices of p |
| `g_fn_handkeeps` | :1429 | `main` | The kept parameters whose value this function keeps ONLY in a struct the program manages by hand through a poi |
| `g_fn_inout` | :1363 | `main` | Per-function inout-parameter map. `g_fn_inout[fname]` is the space-separated list of 0-based indices of `inout |
| `g_fn_invoke_only` | :1475 | `main` | Per-function *invoke-only* parameter map (closure-env reclamation, docs/MEMORY.md §7.4). `g_fn_invoke_only[fna |
| `g_fn_keeps` | :1381 | `main` | Per-function KEPT-parameter map (docs/MEMORY.md §7.6): indices of parameters whose value the body stores somew |
| `g_fn_link_exports` | :1096 | `main` |  |
| `g_fn_link_sources` | :1095 | `main` | Source identities stay unmangled in semantic tables and diagnostics. Only their LLVM linkage names enter the p |
| `g_fn_mutates` | :1579 | `main` | Per-function container-mutation summary (docs/MEMORY.md §2.5). `g_fn_mutates[fname]` lists the 0-based paramet |
| `g_fn_mutates_witness` | :1580 | `gen_call`, `gen_closure_expr`, `gen_fn_decl_concrete` |  |
| `g_fn_noreturn` | :1602 | `main` | Noreturn registry. `g_fn_noreturn[fname]` is `1` when a call to fname never returns to its caller. Seeded with |
| `g_fn_pos_syms` | :1091 | `main` |  |
| `g_fn_reallocs` | :1585 | `main` | `g_fn_reallocs[fname]`: the parameters whose BUFFER the function may move or release (a reallocation, a free)  |
| `g_fn_reallocs_witness` | :1586 | `gen_closure_expr`, `gen_fn_decl_concrete` |  |
| `g_fn_ret_alias` | :1561 | `main` | Per-function returned-HANDLE map — the ownership dual of g_fn_ret_param, and deliberately a separate map rathe |
| `g_fn_ret_count` | :1607 | `gen_fn_decl_concrete`, `gen_ret` | Count of `^` statements seen while compiling the current function body (closure bodies included — that over-co |
| `g_fn_ret_param` | :1547 | `main` | Per-function returned-parameter map. `g_fn_ret_param[fname]` is the space-separated list of 0-based indices of |
| `g_fn_ret_view` | :1461 | `main` | Per-function RETURNS-A-VIEW map. `g_fn_ret_view[fname]` is set when the body builds an aggregate one of whose  |
| `g_fn_safe` | :2478 | `main` |  |
| `g_fn_safe_list` | :2479 | `gen_fn_decl_concrete` |  |
| `g_fn_sink` | :1371 | `main` | Per-function sink-parameter map: space-separated parameter indices from explicit signatures and consuming call |
| `g_fn_slice_decls` | :1045 | `gen_fn_decl_concrete`, `mem_slice_decl_add` | Cheap per-function gate for the Phase 2D slice machinery: most functions declare no owned slices at all, and t |
| `g_fn_stores` | :1422 | `main` | The kept parameters whose value ends up somewhere the compiler drops — a literal, a local struct, a container  |
| `g_fn_unverified` | :1433 | `main` | Retention through an unverified foreign or indirect call. Lifetime-only facts; kept separate from diagnostic e |
| `g_fold_cap` | :49472 | `__fold_touch` |  |
| `g_fold_end` | :49479 | `__fold_flag`, `__fold_reg` |  |
| `g_fold_fcap` | :49478 | `__fold_add_flag` |  |
| `g_fold_flags` | :49465 | `dce_emit_module`, `dce_free` | ── Late flag folding ────────────────────────────────────────────  Whether a callee takes a parameter over (si |
| `g_fold_flist` | :49476 | `__fold_add_flag` |  |
| `g_fold_fn_end` | :49480 | `__ir_fold_range` |  |
| `g_fold_k` | :49481 | `__fold_operand` |  |
| `g_fold_map` | :49471 | `__fold_touch` | Six words per register: 0 kind (0 none, 1 i1 constant, 2 text alias), 1-2 the constant or the alias's byte ran |
| `g_fold_nf` | :49477 | `__fold_add_flag`, `__fold_reset`, `__ir_fold_range` |  |
| `g_fold_nt` | :49474 | `__fold_reset`, `__fold_touch` |  |
| `g_fold_tcap` | :49475 | `__fold_touch` |  |
| `g_fold_touched` | :49473 | `__fold_touch` |  |
| `g_fold_x` | :49482 | `__fold_last_arg`, `__fold_operand`, `__fold_store_flag` |  |
| `g_fold_y` | :49483 | `__fold_last_arg`, `__fold_operand`, `__fold_store_flag` |  |
| `g_func_count` | :1256 | `gen_call_kwargs`, `gen_closure_expr`, `main`, `store_closure_func` |  |
| `g_generic_struct_syms` | :1049 | `main` |  |
| `g_generic_syms` | :1048 | `main` |  |
| `g_hmemo_depth` | :40599 | `__hmemo_close`, `__hmemo_open` |  |
| `g_hmemo_log` | :40598 | `__hmemo_close`, `__hmemo_open` | ── Coinductive memo for the handle predicates ─────────────────────  `__is_owned_struct_ty` and `__clone_suppo |
| `g_impl_name_syms` | :1054 | `main` |  |
| `g_impl_pos_syms` | :1120 | `main` | `@ fname` scan registration. Two files are free to each have a private `__get`-style helper IN THEIR OWN HEADS |
| `g_impl_ret_syms` | :1053 | `main` |  |
| `g_impl_trait_syms` | :1055 | `main` |  |
| `g_in_match_arm` | :1035 | `gen_match` | Non-zero while parsing a `??` match-arm body. The XOR-confusion warning in gen_ret keys off "a non-terminator  |
| `g_in_unsafe` | :2413 | `gen_fn_decl_concrete` | 1 while the body of an `unsafe` function (or of a closure inside one) is being compiled. |
| `g_init_terminated` | :2565 | `gen_let_or_struct` | g_init_terminated — 1 while a `:` binding's own INITIALISER terminated the block and the statement's remaining |
| `g_input_key` | :49400 | `main` |  |
| `g_input_source` | :49399 | `main` | Borrowed aliases to main's live source/key bindings when --stdin supplies an overlay. Every source read (inclu |
| `g_inst_done` | :44414 | `flush_deferred_instantiations` | flush_deferred_instantiations: emit all queued generic instantiations. Re-reads count each iteration so transi |
| `g_inst_tmpl` | :2423 | `emit_one_instantiation` | The template a generic instance is being compiled from (its unsafe-ness). |
| `g_last_cast_direct` | :1014 | `gen_cast` | 1 when the last cast cast a binding (gen_cast; gen_agg_lit reads it) |
| `g_last_closure_cs` | :1205 | `gen_closure_expr` |  |
| `g_last_closure_nonsend` | :1168 | `gen_closure_expr` | record per impl block, verified after scan_fn_sigs once every impl across the program (incl. imports) is regis |
| `g_last_closure_sharedmut` | :1195 | `gen_call`, `gen_closure_expr` | Thread-safety, the SHARED-MUTATION half (docs/MEMORY.md §6.5). Set to the offending binding name while a closu |
| `g_last_type_ptr` | :8432 | `nurl_set_last_type` |  |
| `g_lazy` | :37900 | `__compile_pipeline` |  |
| `g_lazy_edges` | :37915 | `__compile_pipeline`, `lazy_reach` | The program's reference graph, collected while scan_fn_sigs walks every file (0 when lazy compilation cannot r |
| `g_lazy_force` | :37902 | `__lazy_emit`, `emit_missing_defaults`, `emit_one_instantiation` |  |
| `g_lazy_live` | :37917 | `lazy_reach` | The functions lazy_reach found reachable from the roots: compiled in place. |
| `g_lazy_queue` | :37904 | `__lazy_scan`, `lazy_flush` |  |
| `g_lazy_root` | :37901 | `__compile_pipeline` |  |
| `g_lazy_scan` | :37903 | `__lazy_scan` |  |
| `g_lazy_trace` | :37905 | `__compile_pipeline` |  |
| `g_lib_kind_memo` | :2475 | `main` |  |
| `g_lint` | :2550 | `main` | Unused-symbol lint (opt-in via `--lint`). Default OFF so ordinary builds — and the compiler's own bootstrap, w |
| `g_lint_fpend` | :2556 | `lint_init` | g_lint_fpend — the redundant-free lint's pending release calls (see lint_free_cand). |
| `g_lint_gen` | :2557 | `lint_fn_begin` |  |
| `g_lint_reads` | :2553 | `lint_init` |  |
| `g_lint_recording` | :2572 | `__compile_pipeline` | 1 only during the main parse_program pass. Cleared before flush_deferred_instantiations so synthetic generic m |
| `g_lint_syms` | :2551 | `lint_init` |  |
| `g_lint_used` | :2552 | `lint_init` |  |
| `g_live_lexers` | :8632 | `nurl_lex_free`, `nurl_lex_new` |  |
| `g_live_symtables` | :8631 | `nurl_sym_free`, `nurl_sym_new` |  |
| `g_lock_depth` | :1221 | `gen_call`, `gen_closure_expr` | Lock depth, for the same check. A mutation of shared contents is only a race when nothing serialises it, so th |
| `g_loop_break_used` | :1615 | `main` | `g_loop_break_used[exit_label]` is `1` when a `break` targeting that loop's exit label was compiled. Exit labe |
| `g_loop_nest` | :1316 | `gen_foreach`, `gen_loop` |  |
| `g_loop_serial` | :1409 | `gen_foreach`, `gen_loop` |  |
| `g_lsrc_imemo` | :2433 | `resolve_deferred_borrowck` | …and as bits per callee (mem_fn_lends_arg). |
| `g_lsrc_memo` | :2431 | `resolve_deferred_borrowck` | What each callee lends (mem_fn_lend_sources), once every summary is final: the deferred walks' memo, 0 outside |
| `g_match_ser` | :1315 | `gen_match` |  |
| `g_maybe_moved` | :1285 | `main` |  |
| `g_member_obj` | :1320 | `gen_call`, `gen_ident`, `gen_member` |  |
| `g_member_path` | :2454 | `gen_member` |  |
| `g_member_path_on` | :2453 | `gen_agg_lit`, `gen_assign`, `gen_call`, `gen_cond` +2 | The field path the last member read named (`. . s a h` → `s.a.h`; an element read through a pointer is the poi |
| `g_mono_tparam_tys` | :1676 | `emit_one_instantiation` | Space-separated list of the concrete type-arguments substituted for a generic function's type parameters in th |
| `g_mp` | :49505 | `__jrnl_elide`, `__mp_compute` | ── Journal elision ───────────────────────────────────────────────── A temporary registered with the panic jou |
| `g_nl_buf` | :36993 | `__nl_pad` | N newlines — the re-lex padding that maps a template buffer's line 1 onto the template's real source line (see |
| `g_noaddr_visiting` | :1311 | `__ty_no_address` |  |
| `g_origin_functions` | :35022 | `main` |  |
| `g_origin_named` | :35020 | `origin_free`, `origin_summary` |  |
| `g_origin_nodes` | :35019 | `origin_free`, `origin_new` | Return-escape inference (docs/MEMORY.md §2.8): record that the enclosing function may RETURN this bare-identif |
| `g_origin_returns` | :35023 | `main` |  |
| `g_origin_work` | :35021 | `origin_free`, `origin_queue`, `origin_resolve` |  |
| `g_owned_globals` | :1018 | `gen_const_decl` | Names of the mutable string globals that own their buffer (each has a compiler-emitted `<name>__nurlown` flag) |
| `g_pending_escape` | :1501 | `main` | Deferred interprocedural-escape checks (docs/MEMORY.md §3 forward / generic boundary). A stack reference passe |
| `g_pending_impl` | :1523 | `main` | Deferred summary IMPLICATIONS (docs/MEMORY.md §2.7 / §2.8). A summary is inferred as each body compiles, so a  |
| `g_pending_inline` | :2379 | `gen_fn_decl_concrete`, `parse_toplevel_decl`, `scan_fn_sigs` | g_pending_inline is the `inline` prefix's counterpart to g_pending_simd: set when the parser consumes a TT_INL |
| `g_pending_pub` | :2368 | `parse_toplevel_decl`, `scan_fn_sigs`, `vis_take_pending_pub` | Visibility (grammar v2.0). Tracks the source-file of every @-defined function and per-file strict-mode opt-in. |
| `g_pending_simd` | :2374 | `gen_fn_decl_concrete`, `parse_toplevel_decl`, `scan_fn_sigs` | g_pending_simd is the `simd` prefix's counterpart to g_pending_pub: set when the parser consumes a TT_SIMD ahe |
| `g_pending_unsafe` | :2381 | `gen_fn_decl_concrete`, `parse_toplevel_decl`, `scan_fn_sigs` | The `unsafe` prefix parsed ahead of the next declaration. |
| `g_priv_file_count` | :1087 | `priv_file_id` |  |
| `g_priv_file_ids` | :1086 | `main` | `??`/`?` arms). Consumers that NEED a value (a cast, a let/assign) die with this appended, so "produced no val |
| `g_priv_owner_files` | :1089 | `main` |  |
| `g_priv_owner_ids` | :1088 | `main` |  |
| `g_priv_warned` | :1090 | `main` |  |
| `g_pt_star` | :593 | `parse_type_paren`, `parse_type_ptr` | Raw-pointer types parse_type has read (`*T` anywhere but inside a closure type): a struct field whose type mov |
| `g_ptr_own_n` | :1319 | `__ptr_own_set`, `gen_fn_decl_concrete` |  |
| `g_ptrtab` | :1306 | `main` |  |
| `g_rawlit_n` | :1322 | `gen_fn_decl_concrete`, `mem_note_rawlit` |  |
| `g_rawlit_pending` | :1321 | `gen_agg_lit`, `gen_fn_decl_concrete`, `mem_note_rawlit`, `mem_rawlit_unclaimed` |  |
| `g_rawret_memo` | :21348 | `__fn_raw_ret` |  |
| `g_res_type_syms` | :371 | `main` | ── Res-type NURL tracking (must be declared before parse_type_res) ── g_res_type_syms is initialized to a new  |
| `g_ret_forbidden` | :1029 | `gen_cond`, `gen_logical_or_bitwise_and`, `gen_logical_or_bitwise_or`, `gen_operand` +1 | Cascade guard: 1 while parsing a VALUE OPERAND (a binary/unary/cast/ member operand, a call argument, a `?`/`? |
| `g_retclo_n` | :1323 | `gen_fn_decl_concrete` |  |
| `g_root_syms` | :1385 | `main` | The module's root symbol table, for the type questions asked where no table is at hand (__is_handle_ty on a st |
| `g_rpg_cur` | :21546 | `__rpg_enter` |  |
| `g_rpg_cur_id` | :21547 | `__rpg_enter` |  |
| `g_rpg_cur_pfx` | :21548 | `__rpg_enter` |  |
| `g_rpg_ecap` | :21563 | `__rpg_edge_push` |  |
| `g_rpg_edge` | :21561 | `__rpg_edge_push` |  |
| `g_rpg_f` | :21558 | `__rpg_fn_id` | A function's row, RPG_FW words: 0 its name (a copy), 1 1 when it has records, 2 what its other summaries say i |
| `g_rpg_fcap` | :21560 | `__rpg_fn_id` |  |
| `g_rpg_fid` | :21549 | `__rpg_fn_id` |  |
| `g_rpg_list` | :36296 | `resolve_raw_provenance` | The records of function `f`, in order: g_rpg_list[ row 11 .. next ). |
| `g_rpg_me_id` | :21565 | `__mut_edge_note`, `gen_fn_decl_concrete` |  |
| `g_rpg_me_self` | :21564 | `gen_fn_decl_concrete` |  |
| `g_rpg_names` | :21545 | `__rpg_enter` |  |
| `g_rpg_nedge` | :21562 | `__rpg_edge_push` |  |
| `g_rpg_nfn` | :21559 | `__rpg_fn_id` |  |
| `g_rpg_nrec` | :21538 | `__rpg_push` |  |
| `g_rpg_nslot` | :21543 | `__rpg_slot` |  |
| `g_rpg_on` | :2421 | `gen_fn_decl_concrete` | …and its graph is recorded (g_rpg): raw code with a parameter that can hold storage. Without one, nothing the  |
| `g_rpg_rcap` | :21539 | `__rpg_push` |  |
| `g_rpg_rec` | :21537 | `__rpg_push` |  |
| `g_rpg_scap` | :21544 | `__rpg_slot` |  |
| `g_rpg_sname` | :21542 | `__rpg_slot` |  |
| `g_rpg_tmp` | :21803 | `__rprov_lend_expr` | A returned pointer (or a returned literal's pointer field) whose expression read `reads`: bound to a name of i |
| `g_rpg_u` | :21541 | `__rpg_slot` |  |
| `g_rpg_v` | :21540 | `__rpg_slot` |  |
| `g_rprov_on` | :2417 | `gen_fn_decl_concrete` | Raw provenance is followed in this body (__rprov_note): it is raw code, an `unsafe` function or the trusted st |
| `g_sanitize_address` | :49392 | `main` | Emission policy, set by main's --sanitize-address flag. |
| `g_simd_fns` | :2515 | `emit_multiversion` | Every `simd` function emit_multiversion has written, by its IR name (`__nurl_fn.f`), space-separated. The spli |
| `g_sound` | :22677 | `bck_sound` | The sound-and-complete rules (docs/SOUND_COMPLETE_PLAN.md): moves and borrows. Under development they run when |
| `g_source_snapshots` | :49401 | `compiler_read_source`, `main` |  |
| `g_sp_pin` | :51494 | `__sp_pin_free`, `__sp_pin_simd` |  |
| `g_sp_pq` | :51495 | `__sp_pin_free`, `__sp_pin_simd` |  |
| `g_sp_pqn` | :51496 | `__sp_pin_free`, `__sp_pin_name`, `__sp_pin_simd` |  |
| `g_split_fh` | :49258 | `__sp_close`, `__sp_open` |  |
| `g_split_fill` | :49256 | `split_emit_module` |  |
| `g_split_max` | :49252 | `main` |  |
| `g_split_min` | :49253 | `main` |  |
| `g_split_n` | :49251 | `__sp_whole`, `dce_emit_module`, `split_emit_module` | Partitioned emission — see "Partitioned emission" below. |
| `g_split_out` | :49254 | `main` |  |
| `g_split_part` | :49255 | `split_emit_module` |  |
| `g_split_priv` | :49257 | `split_emit_module` |  |
| `g_srcx_on` | :2467 | `gen_fn_decl_concrete` | Source expressions (srcx): where a view's value came from, as an expression the walk evaluates once every summ |
| `g_stmt_bare_lit` | :4959 | `gen_stmt` | g_stmt_bare_lit — set by gen_stmt to 1 when the statement it just parsed was a bare numeric/string LITERAL in  |
| `g_stmt_bare_value` | :4986 | `gen_stmt` | g_stmt_bare_value — the literal flag's general sibling (critic A2, the last silent prefix-arity cascade): set  |
| `g_stmt_col` | :4802 | `gen_block_ret`, `gen_stmt` | g_stmt_col — column of the current statement's first token, captured alongside g_stmt_line. `die_stmt` anchors |
| `g_stmt_line` | :4795 | `gen_block_ret`, `gen_stmt` | g_stmt_line — source line of the statement gen_stmt is currently parsing. Read by gen_ident's "unexpected toke |
| `g_str_idx` | :1010 | `emit_deferred_cstr`, `emit_str_global`, `gen_str_lit` |  |
| `g_str_syms` | :1011 | `main` |  |
| `g_strict_arity` | :1296 | `main` | strict-arity: the n-ary `&`/`\|` arity trap is an ERROR by default. The trap is the language's one documented f |
| `g_strict_borrowck` | :1284 | `main` | `--strict-borrowck` (off by default) enables three additional checks: (1) aliased mutation through `. obj fiel |
| `g_struct_inst_syms` | :1052 | `main` | <sname>__stparams → space-separated type-var names (e.g. "T" or "K V") <sname>__sbody    → raw body source inc |
| `g_struct_tmp` | :1489 | `gen_call`, `gen_closure_expr`, `gen_fn_decl_concrete`, `mem_clo_drop_discarded` | The struct temporary with owned fields most recently returned by a call, as `<value> <%Type> <owned-field toke |
| `g_summaries_final` | :1314 | `mem_emit_arg_flags` |  |
| `g_super_obligations` | :1158 | `scan_impl_decl` |  |
| `g_sx` | :2492 | `__sx_publish` |  |
| `g_sx_at` | :2491 | `__sx_publish` |  |
| `g_sx_n` | :2490 | `__sx_enter` |  |
| `g_sxe_pos` | :23928 | `bck_sx_arg_sources`, `bck_sx_ev`, `bck_sx_skip`, `bck_sx_sources` | ── Source expressions in the walk ── The cursor of the evaluation in progress (bck_sx_sources), and whether it |
| `g_trait_pending` | :1141 | `main` | <Trait>__tparam           → trait's generic type-var name (e.g. "T") <Trait>__defaults         → space-separat |
| `g_trait_syms` | :1127 | `main` | first registration. A `$`-imported impl is scanned once per importer, so the SAME (method, type) is registered |
| `g_type_count` | :1255 | `main`, `store_closure_type` |  |
| `g_type_emit_base` | :1258 | `main` |  |
| `g_type_layouts` | :1437 | `main` | Type layout metadata precedes cleanup decisions; IR definitions retain their source ordering. This table owns  |
| `g_udrop_noinit` | :1414 | `gen_let_or_struct`, `mem_own_add_user_drop` | Set by a `:` binding just before registering its value: the binding rule stores the drop flag itself, so regis |
| `g_unsafe_fns` | :2383 | `gen_trait_or_impl`, `scan_fn_sigs` | The functions declared `unsafe` (name → 1; 0 until the first one). |
| `g_unsafe_list` | :2404 | `note_unsafe_fn` |  |
| `g_unsafe_report` | :2403 | `main` | `--unsafe-report`: the program's own `unsafe` functions (outside the standard library), one `file:line name` p |
| `g_use_argxfer` | :1389 | `mem_emit_string_arg_transfers` |  |
| `g_use_clear_if` | :1388 | `mem_udrop_flag_clear_if` | Whether this module calls the drop-flag helpers (emitted at module end). |
| `g_use_hown` | :1390 | `emit_dyn_method_thunk`, `mem_capture_hown`, `mem_publish_hown` |  |
| `g_user_drop_seen` | :148 | `emit_dyn_drop_fn`, `scan_impl_decl` | 1 once the program declares a `% Drop` impl of its own (scan_impl_decl): until then no type has one, and the q |
| `g_ut_gen` | :2439 | `bck_unsafe_ctx` |  |
| `g_vctl_seen` | :2386 | `gen_call`, `gen_fn_decl_concrete`, `mem_note_velem` | Set by a call to nurl_vctl_data; the let that binds its result marks the pointer `__velem` (its element access |
| `g_vis_file_gen` | :2438 | `vis_set_current_src_file` |  |
| `g_vis_inst_targs` | :1679 | `ensure_struct_instantiated` | The type arguments of the generic struct being instantiated (its field types are parsed in a pseudo-file); see |
| `g_vis_syms` | :2369 | `main` |  |
| `g_void_reason` | :1056 | `__void_reason_clear`, `gen_cond`, `gen_match`, `int_width` |  |
| `g_xl_cap` | :2501 | `bck_xl_room` |  |
| `g_xl_depth` | :2497 | `bck_xl_close`, `bck_xl_open`, `bck_xl_reset` | The frame depth and renames of the lexical scopes the borrow walk's rows are translated in (bck_xl_declare_id) |
| `g_xl_nser` | :2502 | `bck_xl_open`, `bck_xl_reset` |  |
| `g_xl_op` | :2500 | `bck_xl_room` |  |
| `g_xl_ren` | :2498 | `bck_xl_declare_id`, `bck_xl_reset` |  |
| `g_xl_ss` | :2499 | `bck_xl_room` |  |

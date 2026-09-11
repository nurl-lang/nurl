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
| input snapshot | `g_input_source`, `g_input_key` | borrowed aliases of main's live owned stdin source and canonical logical path; `compiler_read_source` returns owned copies to every replay/diagnostic reader; zero in ordinary file mode |
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
  strings by index instead of re-slicing remainders (`__bck_st_get_at`
  is the pattern), and build outputs in one exact-size buffer instead
  of concat-accumulating.
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
| `g_arg_ident_log` | :1070 | `gen_call`, `gen_ident` | --strict-borrowck only: every binding NAME read while generating the current call argument, including reads ne |
| `g_auto_drop_strings` | :1954 | `main` | Phase 2B auto-drop-strings feature flag. Default ON. Compiler's own source uses patterns (strings stored via n |
| `g_bck` | :1192 | `main` |  |
| `g_bck_cap_names` | :1127 | `bck_add_cap_name`, `bck_fn_begin`, `gen_closure_expr` | Names of `:`-bound closures in the CURRENT function whose capture list is non-empty — the allocation-free pre- |
| `g_bck_cap_via` | :1138 | `bck_fn_begin`, `bck_note_closure_caps`, `gen_closure_expr`, `resolve_deferred_borrowck` | `<handle> <closure>` pairs for the current function: which closure binding made a captured handle reachable at |
| `g_bck_closure_depth` | :1212 | `gen_closure_expr` |  |
| `g_bck_depth` | :1195 | `bck_block_enter`, `bck_block_exit`, `bck_fn_begin`, `gen_closure_expr` | data (statement list etc.); allocated in main() only when --borrowck is set |
| `g_bck_errors` | :1216 | `bck_emit_error` | capture hooks no-op so closure statements do not inline into the enclosing function's list (so closure scopes  |
| `g_bck_gen` | :1196 | `bck_analyze` |  |
| `g_bck_inn` | :1200 | `bck_analyze`, `bck_intern` | intern table — bumped per bck_analyze so entries from earlier functions read as misses without any table clear |
| `g_bck_rec_off` | :1211 | (init only) | >0 while the borrow checker's capture hooks must not record. Used to be spelled `g_bck_closure_depth != 0`, wh |
| `g_blk_tail_lit_col` | :3633 | `gen_block_expr`, `gen_block_ret` |  |
| `g_blk_tail_lit_line` | :3632 | `gen_block_expr`, `gen_block_ret`, `gen_block_stmts`, `gen_cond` +1 | g_blk_tail_lit_line/col — the dangling-literal exemption's escape hatch, closed. A bare literal as a value blo |
| `g_borrowck` | :1153 | `main` | ── Borrow-checker state ───────────────────────────────────────── g_borrowck is 1 (ON) by default; `--no-borro |
| `g_closure_consumed` | :1117 | `bck_stash_move`, `gen_closure_expr` | Names a closure BODY consumed. bck_stash_move drops its records while inside a closure — the body's statements |
| `g_closure_defs` | :1139 | `main` |  |
| `g_closure_emit_base` | :1143 | `emit_closure_globals`, `main` |  |
| `g_closure_types` | :1140 | `main` |  |
| `g_cond_depth` | :1190 | `gen_cond`, `gen_loop` | Nesting depth of "we are parsing an enclosing construct's CONDITION". The arity check above fires when a `{` f |
| `g_cpu_dispatch` | :1995 | `main` | Which wider ISA the `simd` prefix dispatches to. 1 = x86-64-v3 (AVX2 + BMI2 + FMA), 0 = no dispatch, emit the  |
| `g_cur_ret_llty` | :133 | `gen_fn_decl_concrete` | LLVM return type of the function whose body is currently being generated. Diagnostics-only: gen_field_store co |
| `g_dbg_blob_syms` | :1432 | `dbg_init` | module-flag id we might add later |
| `g_dbg_cu_id` | :1435 | `dbg_init` |  |
| `g_dbg_current_file_id` | :1464 | `gen_fn_decl_concrete` | defining path for the mono being emitted (the mono's lexer filename is the synthetic `<generic …>`). Set/resto |
| `g_dbg_current_loc` | :1438 | `dbg_synth_begin`, `dbg_synth_end`, `gen_closure_expr`, `gen_fn_decl_concrete` +1 | (0 outside any function) |
| `g_dbg_current_subprogram` | :1436 | `dbg_synth_begin`, `dbg_synth_end`, `gen_closure_expr`, `gen_fn_decl_concrete` |  |
| `g_dbg_enabled` | :1429 | `main` | ── DWARF debug-info state ─────────────────────────────────────── All zero/empty when --g is OFF; emit helpers |
| `g_dbg_file_id` | :1434 | `dbg_init` | flushed at end-of-module by dbg_flush |
| `g_dbg_file_syms` | :1453 | `dbg_init` | uses this instead of `nurl_lex_line` for the !DISubprogram source line. Set by emit_one_instantiation so per-m |
| `g_dbg_next_id` | :1430 | `dbg_alloc_id` |  |
| `g_dbg_override_file` | :1458 | `emit_one_instantiation` | every source file gets its own !DIFile and a subprogram debug-attributes to the file that DEFINES it (imports, |
| `g_dbg_override_line` | :1447 | `emit_one_instantiation` | the type for every local until Phase 6 lays down per-LLVM-type DIBasicType entries indexed by `vt`. |
| `g_dbg_placeholder_ty` | :1443 | `dbg_init` | dbg_init and reused for every fn. Phase 6 will replace with per-fn signature types. |
| `g_dbg_subroutine_ty` | :1440 | `dbg_init` | emit_dbg_eol then omits `, !dbg !N`) |
| `g_dbg_type_syms` | :1482 | `dbg_init` |  |
| `g_dce` | :30806 | `main` |  |
| `g_dce_end` | :30832 | `dce_emit_module`, `dce_free` |  |
| `g_dce_keep` | :30817 | `main` | `--keep=a,b,c` — extra DCE roots.  The pass's root set is `main` plus whatever module-scope constants name. Th |
| `g_dce_live` | :30833 | `dce_emit_module`, `dce_free` |  |
| `g_dce_map` | :30836 | `dce_emit_module`, `dce_free` |  |
| `g_dce_mod` | :30830 | `dce_emit_module` | The module text, as an integer cast of a BORROWED `s`. Deliberately not a `: ~ s` global: a mutable string glo |
| `g_dce_qn` | :30835 | `__dce_mark_name`, `dce_emit_module` |  |
| `g_dce_queue` | :30834 | `dce_emit_module`, `dce_free` |  |
| `g_dce_start` | :30831 | `dce_emit_module`, `dce_free` |  |
| `g_defer_count` | :954 | `gen_defer`, `gen_fn_decl_concrete` |  |
| `g_deferred_bck` | :1347 | `main` | Functions whose borrow-check walk is parked until the whole module has compiled (see borrowck_fn_end). `n` is  |
| `g_diag_ctx` | :124 | `dyn_subst_parts`, `emit_missing_defaults`, `emit_one_instantiation`, `register_missing_defaults` | Diagnostic context suffix, appended to every die/warn message while non-empty. Set (and saved/restored — insta |
| `g_diag_recover_active` | :115 | `main`, `parse_program` |  |
| `g_did_ret` | :921 | `__close_dead_block`, `__handle_unreachable_stmt`, `__tail_noreturn_close`, `gen_closure_expr` +9 |  |
| `g_dyn_dtout` | :1044 | `dyn_method_decltrait` | dyn_method_decltrait's result rides a global too: its callers sit ABOVE its definition, so an owned return wou |
| `g_dyn_flat_out` | :1038 | `__dyn_flat_add`, `__dyn_flat_reset` | Scratch accumulators for dyn_flat_methods (a NURL fn returns one value, so the recursive supertrait walk threa |
| `g_dyn_flat_seen` | :1039 | `__dyn_flat_add`, `__dyn_flat_reset` |  |
| `g_dyn_needed` | :1035 | `dyn_note_needed` | Dynamic trait objects (`%Trait`, docs/spec.md §4.9). Space-separated set of trait names that appear as a `%Tra |
| `g_err_count` | :114 | `__diag_abort` | Multi-error mode (rustc-style): while parse_program's per-declaration recovery frame is active (g_diag_recover |
| `g_ffi_host_imports` | :1160 | `main` | g_ffi_host_imports is 1 when `--ffi-host-imports` is passed: external `&`-FFI libraries are then satisfied by  |
| `g_fn_arc_mut` | :1388 | `main` | Per-function shared-mutation summary (docs/MEMORY.md §6.5). `g_fn_arc_mut[fname]` is `1` when the body mutates |
| `g_fn_arc_mut_witness` | :1091 | `gen_call`, `gen_closure_expr`, `gen_fn_decl_concrete` | Function-level witness for the same property. NOT a symbol-table key: the mutation is usually inside a loop or |
| `g_fn_compiled` | :1353 | `main` | Names of functions whose body has been compiled — the "is the inline summary trustworthy for this callee?" tes |
| `g_fn_embeds` | :1280 | `main` | Per-function EMBEDDED-parameter map. `g_fn_embeds[fname]` is the space-separated list of 0-based indices of pa |
| `g_fn_escapes` | :1260 | `main` | Per-function escaping-parameter map. `g_fn_escapes[fname]` is the space-separated list of 0-based indices of p |
| `g_fn_inout` | :1233 | `main` | Per-function inout-parameter map. `g_fn_inout[fname]` is the space-separated list of 0-based indices of `inout |
| `g_fn_invoke_only` | :1307 | `main` | Per-function *invoke-only* parameter map (closure-env reclamation, docs/MEMORY.md §7.4). `g_fn_invoke_only[fna |
| `g_fn_mutates` | :1397 | `main` | Per-function container-mutation summary (docs/MEMORY.md §2.5). `g_fn_mutates[fname]` lists the 0-based paramet |
| `g_fn_mutates_witness` | :1398 | `gen_call`, `gen_closure_expr`, `gen_fn_decl_concrete` |  |
| `g_fn_noreturn` | :1411 | `main` | Noreturn registry. `g_fn_noreturn[fname]` is `1` when a call to fname never returns to its caller. Seeded with |
| `g_fn_pos_syms` | :998 | `main` |  |
| `g_fn_ret_alias` | :1379 | `main` | Per-function returned-HANDLE map — the ownership dual of g_fn_ret_param, and deliberately a separate map rathe |
| `g_fn_ret_count` | :1416 | `gen_fn_decl_concrete`, `gen_ret` | Count of `^` statements seen while compiling the current function body (closure bodies included — that over-co |
| `g_fn_ret_param` | :1365 | `main` | Per-function returned-parameter map. `g_fn_ret_param[fname]` is the space-separated list of 0-based indices of |
| `g_fn_ret_view` | :1293 | `main` | Per-function RETURNS-A-VIEW map. `g_fn_ret_view[fname]` is set when the body builds an aggregate one of whose  |
| `g_fn_sink` | :1241 | `main` | Per-function sink-parameter map: space-separated parameter indices from explicit signatures and consuming call |
| `g_fn_slice_decls` | :952 | `gen_fn_decl_concrete`, `mem_slice_decl_add` | Cheap per-function gate for the Phase 2D slice machinery: most functions declare no owned slices at all, and t |
| `g_fn_unverified` | :1245 | `main` | Retention through an unverified foreign or indirect call. Lifetime-only facts; kept separate from diagnostic e |
| `g_func_count` | :1142 | `gen_call_kwargs`, `gen_closure_expr`, `main`, `store_closure_func` |  |
| `g_generic_struct_syms` | :956 | `main` |  |
| `g_generic_syms` | :955 | `main` |  |
| `g_have_simd_fn` | :1984 | `emit_multiversion` | Set by emit_multiversion the first time it runs. The splitter reads it and declines to partition the module —  |
| `g_impl_name_syms` | :961 | `main` |  |
| `g_impl_pos_syms` | :1007 | `main` | `@ fname` scan registration. Two files are free to each have a private `__get`-style helper IN THEIR OWN HEADS |
| `g_impl_ret_syms` | :960 | `main` |  |
| `g_impl_trait_syms` | :962 | `main` |  |
| `g_in_match_arm` | :942 | `gen_match` | Non-zero while parsing a `??` match-arm body. The XOR-confusion warning in gen_ret keys off "a non-terminator  |
| `g_input_key` | :30961 | `main` |  |
| `g_input_source` | :30960 | `main` | Borrowed aliases to main's live source/key bindings when --stdin supplies an overlay. Every source read (inclu |
| `g_last_closure_nonsend` | :1055 | `gen_closure_expr` | record per impl block, verified after scan_fn_sigs once every impl across the program (incl. imports) is regis |
| `g_last_closure_sharedmut` | :1082 | `gen_call`, `gen_closure_expr` | Thread-safety, the SHARED-MUTATION half (docs/MEMORY.md §6.5). Set to the offending binding name while a closu |
| `g_last_type_ptr` | :5838 | `nurl_set_last_type` |  |
| `g_lint` | :2019 | `main` | Unused-symbol lint (opt-in via `--lint`). Default OFF so ordinary builds — and the compiler's own bootstrap, w |
| `g_lint_gen` | :2034 | `lint_fn_begin` |  |
| `g_lint_handles` | :2032 | `lint_init` | g_lint_handles — per-function roster of MANUALLY-MANAGED handles (docs/MEMORY.md §7.4: Vec and String, the two |
| `g_lint_reads` | :2022 | `lint_init` |  |
| `g_lint_recording` | :2041 | `__compile_pipeline` | 1 only during the main parse_program pass. Cleared before flush_deferred_instantiations so synthetic generic m |
| `g_lint_released` | :2033 | `lint_init` |  |
| `g_lint_syms` | :2020 | `lint_init` |  |
| `g_lint_used` | :2021 | `lint_init` |  |
| `g_live_lexers` | :5965 | `nurl_lex_free`, `nurl_lex_new` |  |
| `g_live_symtables` | :5964 | `nurl_sym_free`, `nurl_sym_new` |  |
| `g_lock_depth` | :1107 | `gen_call`, `gen_closure_expr` | Lock depth, for the same check. A mutation of shared contents is only a race when nothing serialises it, so th |
| `g_loop_break_used` | :1424 | `main` | `g_loop_break_used[exit_label]` is `1` when a `break` targeting that loop's exit label was compiled. Exit labe |
| `g_mono_tparam_tys` | :1481 | `emit_one_instantiation` | Space-separated list of the concrete type-arguments substituted for a generic function's type parameters in th |
| `g_origin_functions` | :22338 | `main` |  |
| `g_origin_nodes` | :22336 | `origin_free`, `origin_new` | Return-escape inference (docs/MEMORY.md §2.8): record that the enclosing function may RETURN this bare-identif |
| `g_origin_returns` | :22339 | `main` |  |
| `g_origin_work` | :22337 | `origin_free`, `origin_queue`, `origin_resolve` |  |
| `g_owned_globals` | :925 | `gen_const_decl` | Names of the mutable string globals that own their buffer (each has a compiler-emitted `<name>__nurlown` flag) |
| `g_pending_escape` | :1319 | `main` | Deferred interprocedural-escape checks (docs/MEMORY.md §3 forward / generic boundary). A stack reference passe |
| `g_pending_impl` | :1341 | `main` | Deferred summary IMPLICATIONS (docs/MEMORY.md §2.7 / §2.8). A summary is inferred as each body compiles, so a  |
| `g_pending_inline` | :1980 | `gen_fn_decl_concrete`, `parse_toplevel_decl`, `scan_fn_sigs` | g_pending_inline is the `inline` prefix's counterpart to g_pending_simd: set when the parser consumes a TT_INL |
| `g_pending_pub` | :1969 | `parse_toplevel_decl`, `scan_fn_sigs`, `vis_take_pending_pub` | Visibility (grammar v2.0). Tracks the source-file of every @-defined function and per-file strict-mode opt-in. |
| `g_pending_simd` | :1975 | `gen_fn_decl_concrete`, `parse_toplevel_decl`, `scan_fn_sigs` | g_pending_simd is the `simd` prefix's counterpart to g_pending_pub: set when the parser consumes a TT_SIMD ahe |
| `g_priv_file_count` | :994 | `priv_file_id` |  |
| `g_priv_file_ids` | :993 | `main` | `??`/`?` arms). Consumers that NEED a value (a cast, a let/assign) die with this appended, so "produced no val |
| `g_priv_owner_files` | :996 | `main` |  |
| `g_priv_owner_ids` | :995 | `main` |  |
| `g_priv_warned` | :997 | `main` |  |
| `g_ptrtab` | :1191 | `main` |  |
| `g_res_type_syms` | :338 | `main` | ── Res-type NURL tracking (must be declared before parse_type_res) ── g_res_type_syms is initialized to a new  |
| `g_ret_forbidden` | :936 | `gen_cond`, `gen_logical_or_bitwise_and`, `gen_logical_or_bitwise_or`, `gen_operand` +1 | Cascade guard: 1 while parsing a VALUE OPERAND (a binary/unary/cast/ member operand, a call argument, a `?`/`? |
| `g_sanitize_address` | :30955 | `main` | Emission policy, set by main's --sanitize-address flag. |
| `g_split_fh` | :30826 | `__sp_close`, `__sp_open` |  |
| `g_split_fill` | :30824 | `split_emit_module` |  |
| `g_split_max` | :30820 | `main` |  |
| `g_split_min` | :30821 | `main` |  |
| `g_split_n` | :30819 | `__sp_whole`, `dce_emit_module`, `split_emit_module` | Partitioned emission — see "Partitioned emission" below. |
| `g_split_out` | :30822 | `main` |  |
| `g_split_part` | :30823 | `split_emit_module` |  |
| `g_split_priv` | :30825 | `split_emit_module` |  |
| `g_stmt_bare_lit` | :3619 | `gen_stmt` | g_stmt_bare_lit — set by gen_stmt to 1 when the statement it just parsed was a bare numeric/string LITERAL in  |
| `g_stmt_bare_value` | :3646 | `gen_stmt` | g_stmt_bare_value — the literal flag's general sibling (critic A2, the last silent prefix-arity cascade): set  |
| `g_stmt_col` | :3561 | `gen_block_ret`, `gen_stmt` | g_stmt_col — column of the current statement's first token, captured alongside g_stmt_line. `die_stmt` anchors |
| `g_stmt_line` | :3554 | `gen_block_ret`, `gen_stmt` | g_stmt_line — source line of the statement gen_stmt is currently parsing. Read by gen_ident's "unexpected toke |
| `g_str_idx` | :919 | `emit_deferred_cstr`, `emit_str_global`, `gen_str_lit` |  |
| `g_str_syms` | :920 | `main` |  |
| `g_strict_arity` | :1181 | `main` | strict-arity: the n-ary `&`/`\|` arity trap is an ERROR by default. The trap is the language's one documented f |
| `g_strict_borrowck` | :1170 | `main` | `--strict-borrowck` (off by default) enables three additional checks: (1) aliased mutation through `. obj fiel |
| `g_struct_inst_syms` | :959 | `main` | <sname>__stparams → space-separated type-var names (e.g. "T" or "K V") <sname>__sbody    → raw body source inc |
| `g_super_obligations` | :1045 | `scan_impl_decl` |  |
| `g_trait_pending` | :1028 | `main` | <Trait>__tparam           → trait's generic type-var name (e.g. "T") <Trait>__defaults         → space-separat |
| `g_trait_syms` | :1014 | `main` | first registration. A `$`-imported impl is scanned once per importer, so the SAME (method, type) is registered |
| `g_type_count` | :1141 | `main`, `store_closure_type` |  |
| `g_type_emit_base` | :1144 | `main` |  |
| `g_type_layouts` | :1249 | `main` | Type layout metadata precedes cleanup decisions; IR definitions retain their source ordering. This table owns  |
| `g_vis_syms` | :1970 | `main` |  |
| `g_void_reason` | :963 | `__void_reason_clear`, `gen_cond`, `gen_match`, `int_width` |  |

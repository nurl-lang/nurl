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

`compiler/nurlc.nu` is **one self-contained file** (~18.8k lines, no `$`
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

`dce_emit_module` is the only stage that looks at the emitted IR as
*text*. It indexes every `define … }` block, marks the ones reachable
from `main` (roots: `main`, plus anything named between blocks — a
`@__vt.…` vtable constant names its thunks at module scope), and prints
the live sub-sequence. Working on the finished text rather than a
source-level call graph is what keeps it indifferent to how a function
came to exist: closures, monomorphisations, drop glue and dyn thunks are
all just `@name` references by then. Nothing is rewritten or reordered,
only dropped, and dropping something still referenced surfaces as an
undefined symbol at link time.

## 3. Global state — families and owners

~70 globals fall into a dozen families. The generated appendix (§6)
lists every one with its writers; this section is the mental model.
"Sym table" below = the compiler's own scoped string→string map
(`nurl_sym_new/def/get`, push/pop for scopes; `strdup` on both def and
get — returned values are owned copies).

| family | key globals | role & lifetime |
|---|---|---|
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

Reset discipline: everything is initialised in `main()` and the process
compiles exactly one program — **there is no reuse between files**
except via `$` imports walked in the same run. If you add a global,
initialise it in `main()` next to its family and document the writer
set in the appendix (regenerate it — §6).

## 4. Memory discipline

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
  defining a helper *below* its only caller, so no summary exists at
  the call site (hoist it, or rely on the forward-call ownership
  channel); and a mixed join — a borrowed parameter on one arm, a
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
| `g_arg_ident_log` | :1075 | `gen_call`, `gen_ident` | --strict-borrowck only: every binding NAME read while generating the current call argument, including reads ne |
| `g_auto_drop_strings` | :1953 | `main` | Phase 2B auto-drop-strings feature flag. Default ON. Compiler's own source uses patterns (strings stored via n |
| `g_bck` | :1197 | `main` |  |
| `g_bck_cap_names` | :1132 | `bck_add_cap_name`, `bck_fn_begin`, `gen_closure_expr` | Names of `:`-bound closures in the CURRENT function whose capture list is non-empty — the allocation-free pre- |
| `g_bck_cap_via` | :1143 | `bck_fn_begin`, `bck_note_closure_caps`, `gen_closure_expr`, `resolve_deferred_borrowck` | `<handle> <closure>` pairs for the current function: which closure binding made a captured handle reachable at |
| `g_bck_closure_depth` | :1217 | `gen_closure_expr` |  |
| `g_bck_depth` | :1200 | `bck_block_enter`, `bck_block_exit`, `bck_fn_begin`, `gen_closure_expr` | data (statement list etc.); allocated in main() only when --borrowck is set |
| `g_bck_errors` | :1221 | `bck_emit_error` | capture hooks no-op so closure statements do not inline into the enclosing function's list (so closure scopes  |
| `g_bck_gen` | :1201 | `bck_analyze` |  |
| `g_bck_inn` | :1205 | `bck_analyze`, `bck_intern` | intern table — bumped per bck_analyze so entries from earlier functions read as misses without any table clear |
| `g_bck_rec_off` | :1216 | (init only) | >0 while the borrow checker's capture hooks must not record. Used to be spelled `g_bck_closure_depth != 0`, wh |
| `g_blk_tail_lit_col` | :3616 | `gen_block_expr`, `gen_block_ret` |  |
| `g_blk_tail_lit_line` | :3615 | `gen_block_expr`, `gen_block_ret`, `gen_block_stmts`, `gen_cond` +1 | g_blk_tail_lit_line/col — the dangling-literal exemption's escape hatch, closed. A bare literal as a value blo |
| `g_borrowck` | :1158 | `main` | ── Borrow-checker state ───────────────────────────────────────── g_borrowck is 1 (ON) by default; `--no-borro |
| `g_closure_consumed` | :1122 | `bck_stash_move`, `gen_closure_expr` | Names a closure BODY consumed. bck_stash_move drops its records while inside a closure — the body's statements |
| `g_closure_defs` | :1144 | `main` |  |
| `g_closure_emit_base` | :1148 | `emit_closure_globals`, `main` |  |
| `g_closure_types` | :1145 | `main` |  |
| `g_cond_depth` | :1195 | `gen_cond`, `gen_loop` | Nesting depth of "we are parsing an enclosing construct's CONDITION". The arity check above fires when a `{` f |
| `g_cpu_dispatch` | :1994 | `main` | Which wider ISA the `simd` prefix dispatches to. 1 = x86-64-v3 (AVX2 + BMI2 + FMA), 0 = no dispatch, emit the  |
| `g_cur_ret_llty` | :133 | `gen_fn_decl_concrete` | LLVM return type of the function whose body is currently being generated. Diagnostics-only: gen_field_store co |
| `g_dbg_blob_syms` | :1431 | `dbg_init` | module-flag id we might add later |
| `g_dbg_cu_id` | :1434 | `dbg_init` |  |
| `g_dbg_current_file_id` | :1463 | `gen_fn_decl_concrete` | defining path for the mono being emitted (the mono's lexer filename is the synthetic `<generic …>`). Set/resto |
| `g_dbg_current_loc` | :1437 | `dbg_synth_begin`, `dbg_synth_end`, `gen_closure_expr`, `gen_fn_decl_concrete` +1 | (0 outside any function) |
| `g_dbg_current_subprogram` | :1435 | `dbg_synth_begin`, `dbg_synth_end`, `gen_closure_expr`, `gen_fn_decl_concrete` |  |
| `g_dbg_enabled` | :1428 | `main` | ── DWARF debug-info state ─────────────────────────────────────── All zero/empty when --g is OFF; emit helpers |
| `g_dbg_file_id` | :1433 | `dbg_init` | flushed at end-of-module by dbg_flush |
| `g_dbg_file_syms` | :1452 | `dbg_init` | uses this instead of `nurl_lex_line` for the !DISubprogram source line. Set by emit_one_instantiation so per-m |
| `g_dbg_next_id` | :1429 | `dbg_alloc_id` |  |
| `g_dbg_override_file` | :1457 | `emit_one_instantiation` | every source file gets its own !DIFile and a subprogram debug-attributes to the file that DEFINES it (imports, |
| `g_dbg_override_line` | :1446 | `emit_one_instantiation` | the type for every local until Phase 6 lays down per-LLVM-type DIBasicType entries indexed by `vt`. |
| `g_dbg_placeholder_ty` | :1442 | `dbg_init` | dbg_init and reused for every fn. Phase 6 will replace with per-fn signature types. |
| `g_dbg_subroutine_ty` | :1439 | `dbg_init` | emit_dbg_eol then omits `, !dbg !N`) |
| `g_dbg_type_syms` | :1481 | `dbg_init` |  |
| `g_dce` | :29999 | `main` |  |
| `g_dce_end` | :30025 | `dce_emit_module`, `dce_free` |  |
| `g_dce_keep` | :30010 | `main` | `--keep=a,b,c` — extra DCE roots.  The pass's root set is `main` plus whatever module-scope constants name. Th |
| `g_dce_live` | :30026 | `dce_emit_module`, `dce_free` |  |
| `g_dce_map` | :30029 | `dce_emit_module`, `dce_free` |  |
| `g_dce_mod` | :30023 | `dce_emit_module` | The module text, as an integer cast of a BORROWED `s`. Deliberately not a `: ~ s` global: a mutable string glo |
| `g_dce_qn` | :30028 | `__dce_mark_name`, `dce_emit_module` |  |
| `g_dce_queue` | :30027 | `dce_emit_module`, `dce_free` |  |
| `g_dce_start` | :30024 | `dce_emit_module`, `dce_free` |  |
| `g_defer_count` | :959 | `gen_defer`, `gen_fn_decl_concrete` |  |
| `g_deferred_bck` | :1346 | `main` | Functions whose borrow-check walk is parked until the whole module has compiled (see borrowck_fn_end). `n` is  |
| `g_diag_ctx` | :124 | `dyn_subst_parts`, `emit_missing_defaults`, `emit_one_instantiation`, `register_missing_defaults` | Diagnostic context suffix, appended to every die/warn message while non-empty. Set (and saved/restored — insta |
| `g_diag_recover_active` | :115 | `parse_program` |  |
| `g_did_ret` | :926 | `__close_dead_block`, `__handle_unreachable_stmt`, `__tail_noreturn_close`, `gen_closure_expr` +9 |  |
| `g_dyn_dtout` | :1049 | `dyn_method_decltrait` | dyn_method_decltrait's result rides a global too: its callers sit ABOVE its definition, so an owned return wou |
| `g_dyn_flat_out` | :1043 | `__dyn_flat_add`, `__dyn_flat_reset` | Scratch accumulators for dyn_flat_methods (a NURL fn returns one value, so the recursive supertrait walk threa |
| `g_dyn_flat_seen` | :1044 | `__dyn_flat_add`, `__dyn_flat_reset` |  |
| `g_dyn_needed` | :1040 | `dyn_note_needed` | Dynamic trait objects (`%Trait`, docs/spec.md §4.9). Space-separated set of trait names that appear as a `%Tra |
| `g_err_count` | :114 | `__diag_abort` | Multi-error mode (rustc-style): while parse_program's per-declaration recovery frame is active (g_diag_recover |
| `g_ffi_host_imports` | :1165 | `main` | g_ffi_host_imports is 1 when `--ffi-host-imports` is passed: external `&`-FFI libraries are then satisfied by  |
| `g_fn_arc_mut` | :1387 | `main` | Per-function shared-mutation summary (docs/MEMORY.md §6.5). `g_fn_arc_mut[fname]` is `1` when the body mutates |
| `g_fn_arc_mut_witness` | :1096 | `gen_call`, `gen_closure_expr`, `gen_fn_decl_concrete` | Function-level witness for the same property. NOT a symbol-table key: the mutation is usually inside a loop or |
| `g_fn_compiled` | :1352 | `main` | Names of functions whose body has been compiled — the "is the inline summary trustworthy for this callee?" tes |
| `g_fn_embeds` | :1279 | `main` | Per-function EMBEDDED-parameter map. `g_fn_embeds[fname]` is the space-separated list of 0-based indices of pa |
| `g_fn_escapes` | :1259 | `main` | Per-function escaping-parameter map. `g_fn_escapes[fname]` is the space-separated list of 0-based indices of p |
| `g_fn_inout` | :1238 | `main` | Per-function inout-parameter map. `g_fn_inout[fname]` is the space-separated list of 0-based indices of `inout |
| `g_fn_invoke_only` | :1306 | `main` | Per-function *invoke-only* parameter map (closure-env reclamation, docs/MEMORY.md §7.4). `g_fn_invoke_only[fna |
| `g_fn_mutates` | :1396 | `main` | Per-function container-mutation summary (docs/MEMORY.md §2.5). `g_fn_mutates[fname]` lists the 0-based paramet |
| `g_fn_mutates_witness` | :1397 | `gen_call`, `gen_closure_expr`, `gen_fn_decl_concrete` |  |
| `g_fn_noreturn` | :1410 | `main` | Noreturn registry. `g_fn_noreturn[fname]` is `1` when a call to fname never returns to its caller. Seeded with |
| `g_fn_pos_syms` | :1003 | `main` |  |
| `g_fn_ret_alias` | :1378 | `main` | Per-function returned-HANDLE map — the ownership dual of g_fn_ret_param, and deliberately a separate map rathe |
| `g_fn_ret_count` | :1415 | `gen_fn_decl_concrete`, `gen_ret` | Count of `^` statements seen while compiling the current function body (closure bodies included — that over-co |
| `g_fn_ret_param` | :1364 | `main` | Per-function returned-parameter map. `g_fn_ret_param[fname]` is the space-separated list of 0-based indices of |
| `g_fn_ret_view` | :1292 | `main` | Per-function RETURNS-A-VIEW map. `g_fn_ret_view[fname]` is set when the body builds an aggregate one of whose  |
| `g_fn_sink` | :1248 | `main` | Per-function sink-parameter map. `g_fn_sink[fname]` is the space-separated list of 0-based indices of `sink` p |
| `g_fn_slice_decls` | :957 | `gen_fn_decl_concrete`, `mem_slice_decl_add` | Cheap per-function gate for the Phase 2D slice machinery: most functions declare no owned slices at all, and t |
| `g_func_count` | :1147 | `gen_call_kwargs`, `gen_closure_expr`, `main`, `store_closure_func` |  |
| `g_generic_struct_syms` | :961 | `main` |  |
| `g_generic_syms` | :960 | `main` |  |
| `g_have_simd_fn` | :1983 | `emit_multiversion` | Set by emit_multiversion the first time it runs. The splitter reads it and declines to partition the module —  |
| `g_impl_name_syms` | :966 | `main` |  |
| `g_impl_pos_syms` | :1012 | `main` | `@ fname` scan registration. Two files are free to each have a private `__get`-style helper IN THEIR OWN HEADS |
| `g_impl_ret_syms` | :965 | `main` |  |
| `g_impl_trait_syms` | :967 | `main` |  |
| `g_in_match_arm` | :947 | `gen_match` | Non-zero while parsing a `??` match-arm body. The XOR-confusion warning in gen_ret keys off "a non-terminator  |
| `g_last_closure_nonsend` | :1060 | `gen_closure_expr` | record per impl block, verified after scan_fn_sigs once every impl across the program (incl. imports) is regis |
| `g_last_closure_sharedmut` | :1087 | `gen_call`, `gen_closure_expr` | Thread-safety, the SHARED-MUTATION half (docs/MEMORY.md §6.5). Set to the offending binding name while a closu |
| `g_last_type_ptr` | :5524 | `nurl_set_last_type` |  |
| `g_lint` | :2018 | `main` | Unused-symbol lint (opt-in via `--lint`). Default OFF so ordinary builds — and the compiler's own bootstrap, w |
| `g_lint_gen` | :2033 | `lint_fn_begin` |  |
| `g_lint_handles` | :2031 | `lint_init` | g_lint_handles — per-function roster of MANUALLY-MANAGED handles (docs/MEMORY.md §7.4: Vec and String, the two |
| `g_lint_reads` | :2021 | `lint_init` |  |
| `g_lint_recording` | :2040 | `main` | 1 only during the main parse_program pass. Cleared before flush_deferred_instantiations so synthetic generic m |
| `g_lint_released` | :2032 | `lint_init` |  |
| `g_lint_syms` | :2019 | `lint_init` |  |
| `g_lint_used` | :2020 | `lint_init` |  |
| `g_lock_depth` | :1112 | `gen_call`, `gen_closure_expr` | Lock depth, for the same check. A mutation of shared contents is only a race when nothing serialises it, so th |
| `g_loop_break_used` | :1423 | `main` | `g_loop_break_used[exit_label]` is `1` when a `break` targeting that loop's exit label was compiled. Exit labe |
| `g_mono_tparam_tys` | :1480 | `emit_one_instantiation` | Space-separated list of the concrete type-arguments substituted for a generic function's type parameters in th |
| `g_owned_globals` | :930 | `gen_const_decl` | Names of the mutable string globals that own their buffer (each has a compiler-emitted `<name>__nurlown` flag) |
| `g_pending_escape` | :1318 | `main` | Deferred interprocedural-escape checks (docs/MEMORY.md §3 forward / generic boundary). A stack reference passe |
| `g_pending_impl` | :1340 | `main` | Deferred summary IMPLICATIONS (docs/MEMORY.md §2.7 / §2.8). A summary is inferred as each body compiles, so a  |
| `g_pending_inline` | :1979 | `gen_fn_decl_concrete`, `parse_toplevel_decl`, `scan_fn_sigs` | g_pending_inline is the `inline` prefix's counterpart to g_pending_simd: set when the parser consumes a TT_INL |
| `g_pending_pub` | :1968 | `parse_toplevel_decl`, `scan_fn_sigs`, `vis_take_pending_pub` | Visibility (grammar v2.0). Tracks the source-file of every @-defined function and per-file strict-mode opt-in. |
| `g_pending_simd` | :1974 | `gen_fn_decl_concrete`, `parse_toplevel_decl`, `scan_fn_sigs` | g_pending_simd is the `simd` prefix's counterpart to g_pending_pub: set when the parser consumes a TT_SIMD ahe |
| `g_priv_file_count` | :999 | `priv_file_id` |  |
| `g_priv_file_ids` | :998 | `main` | `??`/`?` arms). Consumers that NEED a value (a cast, a let/assign) die with this appended, so "produced no val |
| `g_priv_owner_files` | :1001 | `main` |  |
| `g_priv_owner_ids` | :1000 | `main` |  |
| `g_priv_warned` | :1002 | `main` |  |
| `g_ptrtab` | :1196 | `main` |  |
| `g_res_type_syms` | :343 | `main` | ── Res-type NURL tracking (must be declared before parse_type_res) ── g_res_type_syms is initialized to a new  |
| `g_ret_forbidden` | :941 | `gen_cond`, `gen_logical_or_bitwise_and`, `gen_logical_or_bitwise_or`, `gen_operand` +1 | Cascade guard: 1 while parsing a VALUE OPERAND (a binary/unary/cast/ member operand, a call argument, a `?`/`? |
| `g_split_fh` | :30019 | `__sp_close`, `__sp_open` |  |
| `g_split_fill` | :30017 | `split_emit_module` |  |
| `g_split_max` | :30013 | `main` |  |
| `g_split_min` | :30014 | `main` |  |
| `g_split_n` | :30012 | `__sp_whole`, `dce_emit_module`, `split_emit_module` | Partitioned emission — see "Partitioned emission" below. |
| `g_split_out` | :30015 | `main` |  |
| `g_split_part` | :30016 | `split_emit_module` |  |
| `g_split_priv` | :30018 | `split_emit_module` |  |
| `g_stmt_bare_lit` | :3602 | `gen_stmt` | g_stmt_bare_lit — set by gen_stmt to 1 when the statement it just parsed was a bare numeric/string LITERAL in  |
| `g_stmt_bare_value` | :3629 | `gen_stmt` | g_stmt_bare_value — the literal flag's general sibling (critic A2, the last silent prefix-arity cascade): set  |
| `g_stmt_col` | :3544 | `gen_stmt` | g_stmt_col — column of the current statement's first token, captured alongside g_stmt_line. `die_stmt` anchors |
| `g_stmt_line` | :3537 | `gen_stmt` | g_stmt_line — source line of the statement gen_stmt is currently parsing. Read by gen_ident's "unexpected toke |
| `g_str_idx` | :924 | `emit_deferred_cstr`, `emit_str_global`, `gen_str_lit` |  |
| `g_str_syms` | :925 | `main` |  |
| `g_strict_arity` | :1186 | `main` | strict-arity: the n-ary `&`/`\|` arity trap is an ERROR by default. The trap is the language's one documented f |
| `g_strict_borrowck` | :1175 | `main` | `--strict-borrowck` (off by default) enables three additional checks: (1) aliased mutation through `. obj fiel |
| `g_struct_inst_syms` | :964 | `main` | <sname>__stparams → space-separated type-var names (e.g. "T" or "K V") <sname>__sbody    → raw body source inc |
| `g_super_obligations` | :1050 | `scan_impl_decl` |  |
| `g_trait_pending` | :1033 | `main` | <Trait>__tparam           → trait's generic type-var name (e.g. "T") <Trait>__defaults         → space-separat |
| `g_trait_syms` | :1019 | `main` | first registration. A `$`-imported impl is scanned once per importer, so the SAME (method, type) is registered |
| `g_type_count` | :1146 | `main`, `store_closure_type` |  |
| `g_type_emit_base` | :1149 | `main` |  |
| `g_vis_syms` | :1969 | `main` |  |
| `g_void_reason` | :968 | `__void_reason_clear`, `gen_cond`, `gen_match`, `int_width` |  |

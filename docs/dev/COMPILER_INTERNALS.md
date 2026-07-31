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
 ├─ emit_header                     — module preamble, runtime declares
 ├─ scan_generic_structs (prepass)  — generic struct templates → tables
 ├─ scan_fn_sigs         (prepass)  — every fn signature, follows `$`
 │                                    imports; makes forward calls typed
 ├─ scan_type_names      (prepass)  — struct/enum names → kind table
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

The four `scan_*` prepasses exist so the fused walk never needs a second
look at the source: by the time `parse_program` runs, every signature,
type name, template and dyn-trait requirement is already in a table.

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
| `g_auto_drop_strings` | :1491 | `main` | Phase 2B auto-drop-strings feature flag. Default ON. Compiler's own source uses patterns (strings stored via n |
| `g_bck` | :872 | `main` |  |
| `g_bck_closure_depth` | :881 | `gen_closure_expr` |  |
| `g_bck_depth` | :875 | `bck_block_enter`, `bck_block_exit`, `bck_fn_begin` | data (statement list etc.); allocated in main() only when --borrowck is set |
| `g_bck_errors` | :885 | `bck_emit_error` | capture hooks no-op so closure statements do not inline into the enclosing function's list (so closure scopes  |
| `g_bck_gen` | :876 | `bck_analyze` |  |
| `g_bck_inn` | :880 | `bck_analyze`, `bck_intern` | intern table — bumped per bck_analyze so entries from earlier functions read as misses without any table clear |
| `g_borrowck` | :853 | `main` | ── Borrow-checker state ───────────────────────────────────────── g_borrowck is 1 (ON) by default; `--no-borro |
| `g_closure_defs` | :839 | `main` |  |
| `g_closure_emit_base` | :843 | `emit_closure_globals`, `main` |  |
| `g_closure_types` | :840 | `main` |  |
| `g_dbg_blob_syms` | :969 | `dbg_init` | module-flag id we might add later |
| `g_dbg_cu_id` | :972 | `dbg_init` |  |
| `g_dbg_current_file_id` | :1001 | `gen_fn_decl_concrete` | defining path for the mono being emitted (the mono's lexer filename is the synthetic `<generic …>`). Set/resto |
| `g_dbg_current_loc` | :975 | `dbg_synth_begin`, `dbg_synth_end`, `gen_closure_expr`, `gen_fn_decl_concrete` +1 | (0 outside any function) |
| `g_dbg_current_subprogram` | :973 | `dbg_synth_begin`, `dbg_synth_end`, `gen_closure_expr`, `gen_fn_decl_concrete` |  |
| `g_dbg_enabled` | :966 | `main` | ── DWARF debug-info state ─────────────────────────────────────── All zero/empty when --g is OFF; emit helpers |
| `g_dbg_file_id` | :971 | `dbg_init` | flushed at end-of-module by dbg_flush |
| `g_dbg_file_syms` | :990 | `dbg_init` | uses this instead of `nurl_lex_line` for the !DISubprogram source line. Set by emit_one_instantiation so per-m |
| `g_dbg_next_id` | :967 | `dbg_alloc_id` |  |
| `g_dbg_override_file` | :995 | `emit_one_instantiation` | every source file gets its own !DIFile and a subprogram debug-attributes to the file that DEFINES it (imports, |
| `g_dbg_override_line` | :984 | `emit_one_instantiation` | the type for every local until Phase 6 lays down per-LLVM-type DIBasicType entries indexed by `vt`. |
| `g_dbg_placeholder_ty` | :980 | `dbg_init` | dbg_init and reused for every fn. Phase 6 will replace with per-fn signature types. |
| `g_dbg_subroutine_ty` | :977 | `dbg_init` | emit_dbg_eol then omits `, !dbg !N`) |
| `g_dbg_type_syms` | :1019 | `dbg_init` |  |
| `g_dce` | :21278 | `main` |  |
| `g_dce_end` | :21284 | `dce_emit_module`, `dce_free` |  |
| `g_dce_live` | :21285 | `dce_emit_module`, `dce_free` |  |
| `g_dce_map` | :21288 | `dce_emit_module`, `dce_free` |  |
| `g_dce_mod` | :21282 | `dce_emit_module` | The module text, as an integer cast of a BORROWED `s`. Deliberately not a `: ~ s` global: a mutable string glo |
| `g_dce_qn` | :21287 | `__dce_mark_name`, `dce_emit_module` |  |
| `g_dce_queue` | :21286 | `dce_emit_module`, `dce_free` |  |
| `g_dce_start` | :21283 | `dce_emit_module`, `dce_free` |  |
| `g_defer_count` | :759 | `gen_defer`, `gen_fn_decl_concrete` |  |
| `g_diag_recover_active` | :92 | `parse_program` |  |
| `g_did_ret` | :726 | `gen_closure_expr`, `gen_cond`, `gen_defer`, `gen_fn_decl_concrete` +5 |  |
| `g_dyn_flat_out` | :826 | `__dyn_flat_add`, `__dyn_flat_reset` | Scratch accumulators for dyn_flat_methods (a NURL fn returns one value, so the recursive supertrait walk threa |
| `g_dyn_flat_seen` | :827 | `__dyn_flat_add`, `__dyn_flat_reset` |  |
| `g_dyn_needed` | :823 | `dyn_note_needed` | <Trait>__tparam           → trait's generic type-var name (e.g. "T") <Trait>__defaults         → space-separat |
| `g_err_count` | :91 | `__diag_abort` | Multi-error mode (rustc-style): while parse_program's per-declaration recovery frame is active (g_diag_recover |
| `g_ffi_host_imports` | :860 | `main` | g_ffi_host_imports is 1 when `--ffi-host-imports` is passed: external `&`-FFI libraries are then satisfied by  |
| `g_fn_escapes` | :923 | `main` | Per-function escaping-parameter map. `g_fn_escapes[fname]` is the space-separated list of 0-based indices of p |
| `g_fn_inout` | :902 | `main` | Per-function inout-parameter map. `g_fn_inout[fname]` is the space-separated list of 0-based indices of `inout |
| `g_fn_invoke_only` | :937 | `main` | Per-function *invoke-only* parameter map (closure-env reclamation, docs/MEMORY.md §7.4). `g_fn_invoke_only[fna |
| `g_fn_pos_syms` | :789 | `main` |  |
| `g_fn_ret_param` | :961 | `main` | Per-function returned-parameter map. `g_fn_ret_param[fname]` is the space-separated list of 0-based indices of |
| `g_fn_sink` | :912 | `main` | Per-function sink-parameter map. `g_fn_sink[fname]` is the space-separated list of 0-based indices of `sink` p |
| `g_fn_slice_decls` | :757 | `gen_fn_decl_concrete`, `mem_slice_decl_add` | Cheap per-function gate for the Phase 2D slice machinery: most functions declare no owned slices at all, and t |
| `g_func_count` | :842 | `gen_call_kwargs`, `gen_closure_expr`, `main`, `store_closure_func` |  |
| `g_generic_struct_syms` | :761 | `main` |  |
| `g_generic_syms` | :760 | `main` |  |
| `g_impl_name_syms` | :766 | `main` |  |
| `g_impl_pos_syms` | :798 | `main` | `@ fname` scan registration. Two files are free to each have a private `__get`-style helper IN THEIR OWN HEADS |
| `g_impl_ret_syms` | :765 | `main` |  |
| `g_impl_trait_syms` | :767 | `main` |  |
| `g_in_match_arm` | :747 | `gen_match` | Non-zero while parsing a `??` match-arm body. The XOR-confusion warning in gen_ret keys off "a non-terminator  |
| `g_last_closure_nonsend` | :838 | `gen_closure_expr` | record per impl block, verified after scan_fn_sigs once every impl across the program (incl. imports) is regis |
| `g_last_type_ptr` | :3866 | `nurl_set_last_type` |  |
| `g_lint` | :1531 | `main` | Unused-symbol lint (opt-in via `--lint`). Default OFF so ordinary builds — and the compiler's own bootstrap, w |
| `g_lint_gen` | :1535 | `lint_fn_begin` |  |
| `g_lint_reads` | :1534 | `lint_init` |  |
| `g_lint_recording` | :1542 | `main` | 1 only during the main parse_program pass. Cleared before flush_deferred_instantiations so synthetic generic m |
| `g_lint_syms` | :1532 | `lint_init` |  |
| `g_lint_used` | :1533 | `lint_init` |  |
| `g_mono_tparam_tys` | :1018 | `emit_one_instantiation` | Space-separated list of the concrete type-arguments substituted for a generic function's type parameters in th |
| `g_owned_globals` | :730 | `gen_const_decl` | Names of the mutable string globals that own their buffer (each has a compiler-emitted `<name>__nurlown` flag) |
| `g_pending_escape` | :949 | `main` | Deferred interprocedural-escape checks (docs/MEMORY.md §3 forward / generic boundary). A stack reference passe |
| `g_pending_pub` | :1506 | `parse_toplevel_decl`, `scan_fn_sigs`, `vis_take_pending_pub` | Visibility (grammar v2.0). Tracks the source-file of every @-defined function and per-file strict-mode opt-in. |
| `g_priv_file_count` | :785 | `priv_file_id` |  |
| `g_priv_file_ids` | :784 | `main` | `??`/`?` arms). Consumers that NEED a value (a cast, a let/assign) die with this appended, so "produced no val |
| `g_priv_owner_files` | :787 | `main` |  |
| `g_priv_owner_ids` | :786 | `main` |  |
| `g_priv_warned` | :788 | `main` |  |
| `g_ptrtab` | :871 | `main` |  |
| `g_res_type_syms` | :239 | `main` | ── Res-type NURL tracking (must be declared before parse_type_res) ── g_res_type_syms is initialized to a new  |
| `g_ret_forbidden` | :741 | `gen_cond`, `gen_logical_or_bitwise_and`, `gen_logical_or_bitwise_or`, `gen_operand` +1 | Cascade guard: 1 while parsing a VALUE OPERAND (a binary/unary/cast/ member operand, a call argument, a `?`/`? |
| `g_stmt_bare_lit` | :2625 | `gen_stmt` | g_stmt_bare_lit — set by gen_stmt to 1 when the statement it just parsed was a bare numeric/string LITERAL in  |
| `g_stmt_bare_value` | :2638 | `gen_stmt` | g_stmt_bare_value — the literal flag's general sibling (critic A2, the last silent prefix-arity cascade): set  |
| `g_stmt_col` | :2583 | `gen_stmt` | g_stmt_col — column of the current statement's first token, captured alongside g_stmt_line. `die_stmt` anchors |
| `g_stmt_line` | :2576 | `gen_stmt` | g_stmt_line — source line of the statement gen_stmt is currently parsing. Read by gen_ident's "unexpected toke |
| `g_str_idx` | :724 | `emit_deferred_cstr`, `emit_str_global`, `gen_str_lit` |  |
| `g_str_syms` | :725 | `main` |  |
| `g_strict_borrowck` | :870 | `main` | `--strict-borrowck` (off by default) enables three additional checks: (1) aliased mutation through `. obj fiel |
| `g_struct_inst_syms` | :764 | `main` | <sname>__stparams → space-separated type-var names (e.g. "T" or "K V") <sname>__sbody    → raw body source inc |
| `g_super_obligations` | :828 | `scan_impl_decl` |  |
| `g_trait_syms` | :805 | `main` | first registration. A `$`-imported impl is scanned once per importer, so the SAME (method, type) is registered |
| `g_type_count` | :841 | `main`, `store_closure_type` |  |
| `g_type_emit_base` | :844 | `main` |  |
| `g_vis_syms` | :1507 | `main` |  |
| `g_void_reason` | :768 | `__void_reason_clear`, `gen_cond`, `gen_match`, `int_width` |  |

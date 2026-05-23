// nurlc.nu — NURL compiler written in NURL.
// Grammar: v2.0
//
// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
// Dual-licensed under MIT (LICENSE-MIT) or Apache-2.0 (LICENSE-APACHE) at your option.
// See README.md for details.
//
// Single-pass NURL → LLVM IR compiler.
// All mutable state lives in opaque i64 handles into C runtime objects.
//
// NURL syntax rules used here:
//   ( fn args... )   — function call, ONLY for calls
//   op lhs rhs       — binary op in prefix, NO outer parens
//   ? b-cond then else — b-cond must have type b (bool)
//   | a b , & a b    — logical ops, args must be b
//
// Bootstrap (automated):
//   ./build.sh           (Linux/macOS)
//   build.bat            (Windows)
//
// Manual bootstrap:
//   python compiler/nurlc.py --llvm compiler/nurlc.nu > build/nurlc.ll
//   clang build/nurlc.ll stdlib/runtime.o -o build/nurlc
//
// Self-compile verification:
//   ./build/nurlc compiler/nurlc.nu > build/nurlc2.ll
//   diff build/nurlc.ll build/nurlc2.ll

// ── Token type constants (must match runtime.c §5) ────────────────
: i TT_EOF 0
: i TT_IDENT 1
: i TT_INT 2
: i TT_STR 3
: i TT_BOOL 4
: i TT_TYPE_KW 5
: i TT_AT 6
: i TT_COLON 7
: i TT_EQ 8
: i TT_ARROW 9
: i TT_CARET 10
: i TT_QUEST 11
: i TT_TILDE 12
: i TT_LPAREN 13
: i TT_RPAREN 14
: i TT_LBRACE 15
: i TT_RBRACE 16
: i TT_DOT 17
: i TT_HASH 18
: i TT_BANG 19
: i TT_PLUS 20
: i TT_MINUS 21
: i TT_STAR 22
: i TT_SLASH 23
: i TT_PERCENT 24
: i TT_AMP 25
: i TT_PIPE 26
: i TT_LT 27
: i TT_GT 28
: i TT_EQEQ 29
: i TT_NE 30
: i TT_LE 31
: i TT_GE 32
: i TT_LBRACK 33
: i TT_RBRACK 34
: i TT_FLOAT 35
: i TT_SIZEOF 36
: i TT_SEMICOL 37
: i TT_BACKSLASH 38
: i TT_DOLLAR 39
: i TT_QUESTQUEST 40
: i TT_SHL 41
: i TT_SHR 42
: i TT_ELLIPSIS 43
: i TT_PUB 44
: i TT_CARETCARET 45  // `^^` — bitwise / logical XOR (lexer pairs `^^`)
: i TT_OROR       46  // `||` — short-circuit logical OR  (binary, bool only)
: i TT_ANDAND     47  // `&&` — short-circuit logical AND (binary, bool only)

// ── Abort helpers ─────────────────────────────────────────────────

@ die i lex s msg → v {
    // Format:
    //   file:line:col: msg
    //       <source line>
    //       <spaces>^
    // GCC/Clang-style — parseable by editors and LLM agents consuming
    // the /build_wasm endpoint without regex acrobatics, and with a
    // human-friendly caret pointer for terminal readers.
    : i col ( nurl_lex_col lex )
    : s loc ( nurl_str_cat ( nurl_lex_filename lex )
    ( nurl_str_cat `:` ( nurl_str_cat ( nurl_str_int ( nurl_lex_line lex ) )
    ( nurl_str_cat `:` ( nurl_str_int col ) ) ) ) )
    ( nurl_eprintln ( nurl_str_cat3 loc `: ` msg ) )
    ( nurl_eprintln ( nurl_lex_line_text lex ) )
    ( nurl_eprintln ( nurl_diag_caret col ) )
    ( nurl_exit 1 )
}

// Soft diagnostic — same format as `die` but does not exit. Used for
// non-fatal compiler-detected pitfalls (shadowing, escaping by-ref
// closure captures) so the user sees the gotcha during compile rather
// than at debugger-attached runtime.
@ warn i lex s msg → v {
    : i col ( nurl_lex_col lex )
    : s loc ( nurl_str_cat ( nurl_lex_filename lex )
    ( nurl_str_cat `:` ( nurl_str_cat ( nurl_str_int ( nurl_lex_line lex ) )
    ( nurl_str_cat `:` ( nurl_str_int col ) ) ) ) )
    ( nurl_eprintln ( nurl_str_cat3 loc `: warning: ` msg ) )
    ( nurl_eprintln ( nurl_lex_line_text lex ) )
    ( nurl_eprintln ( nurl_diag_caret col ) )
}

@ expect i lex i tt → v {
    ? != ( nurl_lex_type lex ) tt
    { ( die lex ( nurl_str_cat `unexpected token, expected tt=` ( nurl_str_int tt ) ) ) }
    {}
    ( nurl_lex_advance lex )
}

// is_ident_tok: true if token type is IDENT or TYPE_KW.
@ is_ident_tok i tt → b {
    | == tt TT_IDENT == tt TT_TYPE_KW
}

// is_type_start: true if tt can start a type expression.
@ is_type_start i tt → b {
    | == tt TT_TYPE_KW | == tt TT_IDENT | == tt TT_STAR
    | == tt TT_QUEST | == tt TT_LBRACK | == tt TT_BANG
    | == tt TT_LPAREN == tt TT_PIPE
}

// seq: string equality returning b (bool).
@ seq s a s b → b {
    != 0 ( nurl_str_eq a b )
}

// ── Res-type NURL tracking (must be declared before parse_type_res) ──
// g_res_type_syms is initialized to a new sym handle in main().
// parse_type_res stores "__last_res_nurl__" and "__last_res_err_llvm__" here.
: i g_res_type_syms 0

// ── Type parsing ──────────────────────────────────────────────────

@ llvm_type s ty → s {
    ? ( seq ty `i` ) `i64`
    ? ( seq ty `u` ) `i8`  // unsigned 8-bit byte
    ? ( seq ty `f` ) `double`
    ? ( seq ty `b` ) `i1`
    ? ( seq ty `s` ) `i8*`
    ? ( seq ty `v` ) `void`
    // Fixed-size integer types (grammar v1.8). LLVM doesn't carry
    // signedness in the type — that's encoded in the binding's
    // `__nurl_type` side-channel and consulted at cast / store /
    // signed-op sites. `i*` is signed, `u*` is unsigned.
    ? ( seq ty `i8` ) `i8`
    ? ( seq ty `i16` ) `i16`
    ? ( seq ty `i32` ) `i32`
    ? ( seq ty `i64` ) `i64`
    ? ( seq ty `u16` ) `i16`
    ? ( seq ty `u32` ) `i32`
    ? ( seq ty `u64` ) `i64`
    ? ( seq ty `f32` ) `float`
    ( nurl_str_cat `%` ty )
}

// nurl_type_is_unsigned: predicate driving sext-vs-zext at cast / store
// sites and unsigned-op selection in binops. Centralized here so the
// list of unsigned NURL idents grows in one place.
@ nurl_type_is_unsigned s nt → b {
    ? == 0 ( nurl_str_len nt ) { ^ F } {}
    ? ( seq nt `u` ) { ^ T } {}
    ? ( seq nt `u16` ) { ^ T } {}
    ? ( seq nt `u32` ) { ^ T } {}
    ? ( seq nt `u64` ) { ^ T } {}
    ^ F
}

@ parse_type i lex → s {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_STAR { ^ ( parse_type_ptr lex ) } {}
    ? == tt TT_QUEST { ^ ( parse_type_opt lex ) } {}
    ? == tt TT_LBRACK { ^ ( parse_type_slice lex ) } {}
    ? == tt TT_BANG { ^ ( parse_type_res lex ) } {}
    ? == tt TT_LPAREN { ^ ( parse_type_paren lex ) } {}
    ? == tt TT_PIPE { ^ ( parse_type_enum lex ) } {}
    ( parse_type_base lex )
}

@ parse_type_ptr i lex → s {
    ( nurl_lex_advance lex )
    : s inner ( parse_type lex )
    // void* is invalid in LLVM IR — use i8* instead
    ? ( seq inner `void` ) { ^ `i8*` } { ^ ( nurl_str_cat inner `*` ) }
}

@ parse_type_base i lex → s {
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s v ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        // Side-channel: stash the NURL-source name of the base type so
        // callers (let-stmt, gen_fn_param) can decide signedness for
        // fixed-width integers. Overwritten on every base-type parse —
        // the OUTERMOST base type wins, which is what we want for
        // `: u32 x …` / `: ~ i16 c …` style bindings. Pointers, slices,
        // option/result/etc wrappers don't carry signedness themselves.
        ( nurl_sym_def g_res_type_syms `__last_nurl_type__` v )
        : s lt ( llvm_type v )
        // Cross-file visibility check (grammar v2.0+). If the resolved
        // LLVM type is `%Name` (i.e. user-defined struct/enum, not a
        // builtin), look up the recorded origin in g_vis_syms. The
        // check is a no-op for builtins (their __src_file is unset)
        // and for same-file references.
        ? & != 0 ( nurl_str_len lt ) == ( nurl_str_get lt 0 ) 37
        { ( vis_check_xref lex v `type` ) }
        {}
        ^ lt
    }
    { ( die lex `expected type` ) }
}

@ parse_type_enum i lex → s {
    ( nurl_lex_advance lex )  // consume '|'
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s v ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        ^ ( nurl_str_cat `%` v )
    }
    { ( die lex `expected enum name after |` ) }
}

// sizeof_nurl: compile-time sizeof for known LLVM types (conservative: 8 for unknowns).
@ sizeof_nurl s lty → i {
    ? ( seq lty `void` ) ^ 0
    ? ( seq lty `i64` ) ^ 8
    ? ( seq lty `double` ) ^ 8
    ? ( seq lty `float` ) ^ 4
    ? ( seq lty `i32` ) ^ 4
    ? ( seq lty `i16` ) ^ 2
    ? ( seq lty `i1` ) ^ 1
    ? ( seq lty `i8` ) ^ 1
    ? ( seq lty `i8*` ) ^ 8
    ? == ( nurl_str_get lty - ( nurl_str_len lty ) 1 ) 42 ^ 8 {}
    8
}

// ( @ R P* )  →  { R (i8*, P0, P1, ...)*, i8* }   closure type
// ( IDENT T+ ) →  generic_inst [Group E, currently errors]
@ parse_type_paren i lex → s {
    ( nurl_lex_advance lex )  // consume '('
    ? == ( nurl_lex_type lex ) TT_AT
    { ( nurl_lex_advance lex )  // consume '@'
        : s ret ( parse_type lex )
        : s params ``
        ~ != ( nurl_lex_type lex ) TT_RPAREN {
            : s p ( parse_type lex )
            = params ? == 0 ( nurl_str_len params )
            p
            ( nurl_str_cat params ( nurl_str_cat `, ` p ) )
        }
        ( expect lex TT_RPAREN )  // consume ')'
        // Return a closure struct type: { ret (i8*, params...)*, i8* }
        : s fn_sig ( nurl_str_cat ret ` (i8*` )
        ? != 0 ( nurl_str_len params )
        { = fn_sig ( nurl_str_cat fn_sig ( nurl_str_cat `, ` params ) ) }
        {}
        = fn_sig ( nurl_str_cat fn_sig `)*` )
        ^ ( nurl_str_cat `{ ` ( nurl_str_cat fn_sig `, i8* }` ) )
    }
    {  // Generic type instantiation: ( Name T1 T2 ... ) → %Name__T1__T2
        // Compound type-args (`( Vec ( Pair K V ) )`) recurse into parse_type
        // and re-mangle the resulting `%Name__...` into a single ident-shaped
        // word so the outer mangle composes deterministically.
        ? ( is_ident_tok ( nurl_lex_type lex ) )
        { : s sname ( nurl_lex_val lex )
            ( nurl_lex_advance lex )
            : s mangle_sfx ``
            ~ != ( nurl_lex_type lex ) TT_RPAREN {
                : ~ s ta_lty ``
                ? == ( nurl_lex_type lex ) TT_LPAREN
                { = ta_lty ( parse_type lex ) }
                { : s ta ( nurl_lex_val lex )
                    ( nurl_lex_advance lex )
                    = ta_lty ( llvm_type ta )
                }
                = mangle_sfx ( nurl_str_cat mangle_sfx
                ( nurl_str_cat `__` ( mangle_type ta_lty ) ) )
            }
            ( expect lex TT_RPAREN )
            ^ ( nurl_str_cat `%` ( nurl_str_cat sname mangle_sfx ) )
        }
        { ( die lex `( in type position must be followed by @ or type name` ) ^ `i64` }
    }
}

// compound_field_type: return LLVM type of field idx in a compound aggregate type string.
// Handles { i1, T } (opt/res) and { T*, i64 } (slice). Falls back to i64 for others.
@ compound_field_type s agg_ty i idx → s {
    : i len ( nurl_str_len agg_ty )
    // Opt or res type: starts with "{ i1, "
    ? & >= len 6 ( seq ( nurl_str_slice agg_ty 0 6 ) `{ i1, ` )
    { ? == idx 0 ^ `i1` {}
        ^ ( nurl_str_slice agg_ty 6 - - len 6 2 )
    }
    {}
    // Slice type: ends with ", i64 }"
    ? & >= len 7 ( seq ( nurl_str_slice agg_ty - len 7 7 ) `, i64 }` )
    { ? == idx 1 ^ `i64` {}
        ^ ( nurl_str_slice agg_ty 2 - - len 2 7 )
    }
    {}
    `i64`
}

// ? T  →  { i1, T }
// Side-channel: "__last_opt_nurl_t__" stashes T's NURL source token
// (e.g. "u" / "i32" / "String") so gen_let_or_struct can propagate
// the signedness flag down to the binding for the T-arm payload.
// Single-token T only — paren-compound T (e.g. `( Vec u )`) records the
// leading `(` here and would need the same `__opt_t_llvm__` fallback
// that parse_type_res uses; not yet needed because no `? ( Vec u )`
// site has surfaced.
@ parse_type_opt i lex → s {
    ( nurl_lex_advance lex )
    : s inner_tok ( nurl_lex_val lex )
    : s inner ( parse_type lex )
    ( nurl_sym_def g_res_type_syms `__last_opt_nurl_t__` inner_tok )
    ( nurl_sym_def g_res_type_syms `__last_opt_t_llvm__` inner )
    ( nurl_str_cat `{ i1, ` ( nurl_str_cat inner ` }` ) )
}

// [ T  →  { T*, i64 }
@ parse_type_slice i lex → s {
    ( nurl_lex_advance lex )
    : s inner ( parse_type lex )
    ( nurl_str_cat `{ ` ( nurl_str_cat inner `*, i64 }` ) )
}

// ! T E  →  { i1, i64 }
// Payload field is always i64: integers stored directly, pointers via ptrtoint,
// enums via extractvalue of their i64 tag field.
// NURL source types are stored in g_res_type_syms under keys:
//   "__last_res_nurl__"     → e.g. "! i s"
//   "__last_res_err_llvm__" → LLVM type of E
//   "__last_res_t_llvm__"   → LLVM type of T (used by gen_match's Ok-arm
//                             reconstruction when T's NURL source name
//                             is a parenthesised compound like `( Vec u )`
//                             whose first lexer token is `(` and can't
//                             be looked up directly)
// for compile-time try-propagation type checking.
@ parse_type_res i lex → s {
    ( nurl_lex_advance lex )
    : s lt_tok ( nurl_lex_val lex )  // capture NURL name of T before parse_type consumes it
    : s lt ( parse_type lex )
    : s le_tok ( nurl_lex_val lex )  // capture NURL name of E
    : s le ( parse_type lex )
    ( nurl_sym_def g_res_type_syms `__last_res_nurl__` ( nurl_str_cat4 `! ` lt_tok ` ` le_tok ) )
    ( nurl_sym_def g_res_type_syms `__last_res_err_llvm__` le )
    ( nurl_sym_def g_res_type_syms `__last_res_t_llvm__` lt )
    `{ i1, i64 }`
}

// ── Emit helpers ──────────────────────────────────────────────────

@ emit s line → v { ( nurl_print line ) ( nurl_print `\n` ) }

@ emiti s line → v { ( nurl_print `  ` ) ( nurl_print line ) ( nurl_print `\n` ) }

// DWARF-aware emit helpers live further down (after g_dbg_* globals
// have been declared) — see `emit_dbg_eol` / `emit_call` /
// `emit_call_term` / `emit_inst` below.

// ── String literal encoding ───────────────────────────────────────

: i g_str_idx 0
: i g_str_syms 0  // sym handle for string-literal metadata (never pushed/popped)
: i g_did_ret 0  // set to 1 by gen_ret; checked/reset by gen_cond
: i g_defer_count 0  // number of active defers in the current function
: i g_generic_syms 0  // sym handle for stored generic function templates (Group E)
: i g_generic_struct_syms 0  // generic struct templates (Group E-structs).
//   <sname>__stparams → space-separated type-var names (e.g. "T" or "K V")
//   <sname>__sbody    → raw body source incl. outer "{ ... }"
: i g_struct_inst_syms 0  // dedupe marker — <mangled>__done → "1" once emitted
: i g_impl_ret_syms 0  // Group F: method##llvm_type → ret_type string
: i g_impl_name_syms 0  // Group F: method##llvm_type → mangle_suffix string
: i g_trait_syms 0  // Trait default implementations.
//   <Trait>__tparam           → trait's generic type-var name (e.g. "T")
//   <Trait>__defaults         → space-separated method names with defaults
//   <Trait>__<method>__src    → raw source "params → ret { body }"
: i g_closure_defs 0  // Deferred closure function definitions
: i g_closure_types 0  // Deferred closure type definitions
: i g_type_count 0  // Count of closure types stored
: i g_func_count 0  // Count of closure functions stored
: i g_closure_emit_base 0  // Next func index to emit (watermark)
: i g_type_emit_base 0  // Next type index to emit

// ── Borrow-checker state (see BORROW.md) ─────────────────────────
// g_borrowck is 1 (ON) by default — BORROW.md Phase 8 flipped the
// default once Phases 1/2/3 were proven false-positive-free across
// the whole corpus; `--no-borrowck` turns it back off. The borrow
// checker is a diagnostic-only analysis pass: it never emits IR, so
// a borrow-clean program produces byte-identical IR whether the flag
// is on or off (the bootstrap fixed point is unaffected). All
// borrowck_* state below is untouched when the flag is 0.
: i g_borrowck 1  // 0 when --no-borrowck passed on the CLI
: i g_bck 0       // sym handle for the borrow checker's per-function
                  //  data (statement list etc.); allocated in main()
                  //  only when --borrowck is set
: i g_bck_depth 0 // block-nesting depth during the statement walk
: i g_bck_closure_depth 0 // >0 while parsing a closure body — the bck
                  //  capture hooks no-op so closure statements do not
                  //  inline into the enclosing function's list
                  //  (BORROW.md Phase 1: segregate closure scopes)

// BORROW.md Phase 4 (Option B): per-function inout-parameter map.
// `g_fn_inout[fname]` is the space-separated list of 0-based indices
// of `inout` parameters, recorded by gen_fn_decl_concrete as each
// function is compiled. gen_call consults it to pass those arguments
// by address. Allocated in main(). It is a *codegen-order* table:
// an `inout` function must be defined before it is called (a forward
// call would pass the argument by value and LLVM would reject the
// type mismatch — loud, never silent).
: i g_fn_inout 0

// BORROW.md Phase 4 (Option B): per-function sink-parameter map.
// `g_fn_sink[fname]` is the space-separated list of 0-based indices
// of `sink` parameters. A `sink` parameter consumes (moves) its
// argument: codegen is an ordinary by-value pass (no IR change), and
// gen_call records the argument binding as borrow-checker-moved so
// the caller cannot use it afterwards. Unlike g_fn_inout, a forward
// call needs no guard — it merely misses the move diagnostic, it is
// never miscompiled. Allocated in main().
: i g_fn_sink 0

// ── DWARF debug-info state (see DWARF.md) ────────────────────────
// All zero/empty when --g is OFF; emit helpers then produce IR that
// is byte-identical to a pre-DWARF build. Toggled in main().
: i g_dbg_enabled 0  // 1 when --g passed on the CLI
: i g_dbg_next_id 100  // metadata-id allocator; starts above any
                       //  module-flag id we might add later
: i g_dbg_blob_syms 0  // sym handle holding queued !N = !DI… lines;
                       //  flushed at end-of-module by dbg_flush
: i g_dbg_file_id 0  // !DIFile id (allocated once at startup)
: i g_dbg_cu_id 0  // !DICompileUnit id
: i g_dbg_current_subprogram 0  // current function's !DISubprogram id
                                 //  (0 outside any function)
: i g_dbg_current_loc 0  // current !DILocation id (0 = no location;
                          //  emit_dbg_eol then omits `, !dbg !N`)
: i g_dbg_subroutine_ty 0  // shared !DISubroutineType id; allocated by
                            //  dbg_init and reused for every fn. Phase 6
                            //  will replace with per-fn signature types.
: i g_dbg_placeholder_ty 0  // shared !DIBasicType id (i64-signed) used as
                             //  the type for every local until Phase 6
                             //  lays down per-LLVM-type DIBasicType
                             //  entries indexed by `vt`.
: i g_dbg_override_line 0  // Phase 7: when non-zero, gen_fn_decl_concrete
                            //  uses this instead of `nurl_lex_line` for
                            //  the !DISubprogram source line. Set by
                            //  emit_one_instantiation so per-mono
                            //  subprograms point at the original generic
                            //  decl line, not synthetic `<generic>:1`.
: i g_dbg_type_syms 0  // Phase 6 type-id cache: LLVM type string
                        //  (e.g. `i64`, `i8*`, `%String`) → metadata id
                        //  of its DIBasicType / DIDerivedType /
                        //  DICompositeType. Populated lazily by
                        //  dbg_type_id_for on first reference.

// End-of-line for an instruction that may need a `!dbg` attachment
// (calls + terminators under a !DISubprogram). When DWARF is off, or
// no DILocation has been set, emits a plain `\n` — IR stays byte-
// identical to a pre-DWARF build. Used by emit_call / emit_call_term,
// and inlined at the tail of legacy multi-print call/ret/br sites.
@ emit_dbg_eol → v {
    ? & != g_dbg_enabled 0 != g_dbg_current_loc 0
    { ( nurl_print `, !dbg !` )
      ( nurl_print ( nurl_str_int g_dbg_current_loc ) ) }
    {}
    ( nurl_print `\n` )
}

// Single-string call emitter. `body` excludes the leading two-space
// indent and the trailing newline. Equivalent to `emiti body` when
// DWARF is off, and `  body, !dbg !N\n` when on.
@ emit_call s body → v {
    ( nurl_print `  ` ) ( nurl_print body ) ( emit_dbg_eol )
}

// Same shape as emit_call but semantically for terminators (`ret`,
// conditional `br`, `unreachable`). Verifier requires `!dbg` on these
// under a !DISubprogram, so they share emit_dbg_eol.
@ emit_call_term s body → v {
    ( nurl_print `  ` ) ( nurl_print body ) ( emit_dbg_eol )
}

// Non-call non-terminator instructions (alloca / load / store / gep /
// phi / arithmetic / icmp / extractvalue / insertvalue). Currently a
// thin wrapper around `emiti`; later phases may decide to attach
// `!dbg` to some of these too (for column-precise stepping), at which
// point this helper is the single integration point.
@ emit_inst s body → v { ( emiti body ) }

// ── DWARF helpers (see DWARF.md) ─────────────────────────────────
// Allocate the next metadata id; ids start at 100 (see g_dbg_next_id)
// and increment monotonically. Returned ids are emitted at end-of-
// module by dbg_flush in numeric order.
@ dbg_alloc_id → i {
    : i id g_dbg_next_id
    = g_dbg_next_id + g_dbg_next_id 1
    ^ id
}

// Buffer one `!N = !DI…(…)` definition keyed by its id. The key is
// the decimal id as a string; dbg_flush walks 100..g_dbg_next_id-1
// and emits whichever keys are populated.
@ dbg_buffer_meta i id s def → v {
    ( nurl_sym_def g_dbg_blob_syms ( nurl_str_int id ) def )
}

// One-shot initialisation called from main when --g is on. Allocates
// the file + compile-unit metadata ids, stashes them in globals, and
// buffers the corresponding `!DIFile` / `!DICompileUnit` definitions.
// Subsequent phases (DISubprogram per fn, DILocation per stmt, …)
// reference these ids via `scope: !<g_dbg_file_id>` etc.
@ dbg_init s path → v {
    = g_dbg_blob_syms ( nurl_sym_new )
    = g_dbg_file_id ( dbg_alloc_id )
    = g_dbg_cu_id ( dbg_alloc_id )
    = g_dbg_subroutine_ty ( dbg_alloc_id )
    ( dbg_buffer_meta g_dbg_file_id
        ( nurl_str_cat3
            `!DIFile(filename: "` path `", directory: ".")` ) )
    ( dbg_buffer_meta g_dbg_cu_id
        ( nurl_str_cat3
            `distinct !DICompileUnit(language: DW_LANG_C, file: !`
            ( nurl_str_int g_dbg_file_id )
            `, producer: "nurlc", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug)` ) )
    // One shared !DISubroutineType for every function until Phase 6
    // emits per-signature variants. `!{null}` means "no params, void
    // return"; the verifier accepts it as a placeholder.
    ( dbg_buffer_meta g_dbg_subroutine_ty `!DISubroutineType(types: !{null})` )
    = g_dbg_placeholder_ty ( dbg_alloc_id )
    ( dbg_buffer_meta g_dbg_placeholder_ty
        `!DIBasicType(name: "i", size: 64, encoding: DW_ATE_signed)` )
    = g_dbg_type_syms ( nurl_sym_new )
    ( nurl_sym_def g_dbg_type_syms `i64`
        ( nurl_str_int g_dbg_placeholder_ty ) )
}

// Phase 6 layout helpers: LLVM "natural" alignment + size in BITS for
// the field types NURL actually emits. Used by composite-type emission
// in dbg_type_id_for to compute cumulative field offsets and the total
// struct size. Mapping follows the x86_64 / aarch64 SysV ABI defaults
// LLVM applies absent an explicit DataLayout override: each primitive
// is naturally aligned to its own byte size; pointers + i64 are 8 B;
// i1 occupies one byte in a struct slot.
//
// Unknown / aggregate types (any leading `%`, raw `*`, `[N x …]`)
// fall back to pointer width (64 bits) — they are always either
// pointer-handles or by-pointer references in NURL's lowering.
@ dbg_size_bits s vt → i {
    ? ( seq vt `i1` )     { ^ 8 } {}
    ? ( seq vt `i8` )     { ^ 8 } {}
    ? ( seq vt `i16` )    { ^ 16 } {}
    ? ( seq vt `i32` )    { ^ 32 } {}
    ? ( seq vt `i64` )    { ^ 64 } {}
    ? ( seq vt `float` )  { ^ 32 } {}
    ? ( seq vt `double` ) { ^ 64 } {}
    ^ 64
}

@ dbg_align_bits s vt → i {
    ? ( seq vt `i1` )     { ^ 8 } {}
    ? ( seq vt `i8` )     { ^ 8 } {}
    ? ( seq vt `i16` )    { ^ 16 } {}
    ? ( seq vt `i32` )    { ^ 32 } {}
    ? ( seq vt `i64` )    { ^ 64 } {}
    ? ( seq vt `float` )  { ^ 32 } {}
    ? ( seq vt `double` ) { ^ 64 } {}
    ^ 64
}

// Round `off` up to the next multiple of `align`. Both bit-valued.
@ dbg_align_up i off i align → i {
    ? <= align 1 { ^ off } {}
    : i rem % off align
    ? == rem 0 { ^ off } {}
    ^ + off - align rem
}

// Phase 6: look up (or lazily create) the metadata id corresponding to
// an LLVM type string. The first call for a given `vt` emits a
// !DIBasicType / !DIDerivedType / !DICompositeType into the blob and
// caches the id; later calls return the cached id without re-emitting.
// Self-referential structs are safe — the id is interned before the
// per-field recursion descends back through dbg_type_id_for.
//
// `syms` is the active symbol table (function-local for `:` bindings,
// module-level for params). The composite-type path reads field name
// + type + count keys (<sname>__field_count, <sname>__idx_N__name,
// <sname>__idx_N__type) recorded by gen_struct_decl / the generic
// instantiation emitter. Base / pointer types don't consult syms.
@ dbg_type_id_for s vt i syms → i {
    : s hit ( nurl_sym_get g_dbg_type_syms vt )
    ? != 0 ( nurl_str_len hit ) { ^ ( nurl_str_to_int hit ) } {}
    : i id 0
    // Base types we render with NURL-flavoured names so `print x` in
    // gdb shows "i" / "u8" / "b" instead of "i64" / "i8" / "i1".
    ? ( seq vt `i64` )
        { = id ( dbg_alloc_id )
          ( dbg_buffer_meta id `!DIBasicType(name: "i", size: 64, encoding: DW_ATE_signed)` ) }
    ? ( seq vt `i32` )
        { = id ( dbg_alloc_id )
          ( dbg_buffer_meta id `!DIBasicType(name: "i32", size: 32, encoding: DW_ATE_signed)` ) }
    ? ( seq vt `i16` )
        { = id ( dbg_alloc_id )
          ( dbg_buffer_meta id `!DIBasicType(name: "i16", size: 16, encoding: DW_ATE_signed)` ) }
    ? ( seq vt `i8` )
        { = id ( dbg_alloc_id )
          ( dbg_buffer_meta id `!DIBasicType(name: "u8", size: 8, encoding: DW_ATE_unsigned)` ) }
    ? ( seq vt `i1` )
        { = id ( dbg_alloc_id )
          ( dbg_buffer_meta id `!DIBasicType(name: "b", size: 8, encoding: DW_ATE_boolean)` ) }
    ? ( seq vt `double` )
        { = id ( dbg_alloc_id )
          ( dbg_buffer_meta id `!DIBasicType(name: "f", size: 64, encoding: DW_ATE_float)` ) }
    ? ( seq vt `float` )
        { = id ( dbg_alloc_id )
          ( dbg_buffer_meta id `!DIBasicType(name: "f32", size: 32, encoding: DW_ATE_float)` ) }
    ? ( seq vt `i8*` )
        { = id ( dbg_alloc_id )
          : i u8_id ( dbg_type_id_for `i8` syms )
          ( dbg_buffer_meta id
            ( nurl_str_cat3
                `!DIDerivedType(tag: DW_TAG_pointer_type, baseType: !`
                ( nurl_str_int u8_id )
                `, size: 64)` ) ) }
    // Named structs (handle: '%' prefix). Try the composite-type path
    // — if syms knows the struct, emit !DICompositeType + per-field
    // !DIDerivedType DW_TAG_member entries. Otherwise fall through.
    ? & == id 0 == 37 ( nurl_str_get vt 0 )
        { = id ( dbg_emit_composite vt syms ) }
    // Everything else (closures, slices, [N x T] arrays, unknown):
    // i64 placeholder so the verifier accepts the DILocalVariable.
    ? == id 0 { = id g_dbg_placeholder_ty } {}
    ( nurl_sym_def g_dbg_type_syms vt ( nurl_str_int id ) )
    ^ id
}

// Phase 6 helper: try to render a `%Name`-prefixed LLVM type string as
// a !DICompositeType with one !DIDerivedType DW_TAG_member per field.
// Returns 0 (caller falls back to the placeholder) when the struct
// is unknown to syms — e.g. an anonymous closure record, an unresolved
// forward decl, or an enum that doesn't carry a field roster.
//
// Self-referential structs (e.g. linked-list cells holding a pointer
// to themselves) are safe: the id is interned in g_dbg_type_syms BEFORE
// the per-field recursion descends — a back-edge through
// dbg_type_id_for returns the cached id instead of recursing forever.
@ dbg_emit_composite s vt i syms → i {
    : s base ( nurl_str_slice vt 1 - ( nurl_str_len vt ) 1 )
    : s is_t ( nurl_sym_get syms ( nurl_str_cat base `__is_type` ) )
    ? == 0 ( nurl_str_len is_t ) { ^ 0 } {}
    : s fc_s ( nurl_sym_get syms ( nurl_str_cat base `__field_count` ) )
    ? == 0 ( nurl_str_len fc_s ) { ^ 0 } {}
    : i n ( nurl_str_to_int fc_s )
    ? <= n 0 { ^ 0 } {}
    // Reserve + intern the composite id BEFORE recursing into fields
    // (self-referential cycle break).
    : i id ( dbg_alloc_id )
    ( nurl_sym_def g_dbg_type_syms vt ( nurl_str_int id ) )
    // First pass: compute layout (cumulative offset + struct size) and
    // emit one !DIDerivedType DW_TAG_member per field. The member-list
    // string is assembled as `!M0, !M1, ...` for the elements: tuple.
    : ~ i off 0
    : ~ i max_align 8
    : ~ s elems ``
    : ~ i fidx 0
    ~ < fidx n {
        : s fname ( nurl_sym_get syms
            ( nurl_str_cat3 base `__idx_` ( nurl_str_cat ( nurl_str_int fidx ) `__name` ) ) )
        : s ftype ( nurl_sym_get syms
            ( nurl_str_cat3 base `__idx_` ( nurl_str_cat ( nurl_str_int fidx ) `__type` ) ) )
        ? == 0 ( nurl_str_len ftype ) { = ftype `i64` } {}
        ? == 0 ( nurl_str_len fname )
            { = fname ( nurl_str_cat `f` ( nurl_str_int fidx ) ) } {}
        : i fsize ( dbg_size_bits ftype )
        : i falign ( dbg_align_bits ftype )
        = off ( dbg_align_up off falign )
        ? > falign max_align { = max_align falign } {}
        : i base_ty_id ( dbg_type_id_for ftype syms )
        : i mid ( dbg_alloc_id )
        ( dbg_buffer_meta mid
            ( nurl_str_cat
                ( nurl_str_cat4
                    `!DIDerivedType(tag: DW_TAG_member, name: "`
                    fname `", baseType: !` ( nurl_str_int base_ty_id ) )
                ( nurl_str_cat4
                    `, size: ` ( nurl_str_int fsize )
                    `, offset: ` ( nurl_str_cat ( nurl_str_int off ) `)` ) ) ) )
        ? == fidx 0
            { = elems ( nurl_str_cat `!` ( nurl_str_int mid ) ) }
            { = elems ( nurl_str_cat3 elems `, !` ( nurl_str_int mid ) ) }
        = off + off fsize
        = fidx + fidx 1
    }
    // Round total size up to the strictest field alignment (LLVM does
    // the same so sizeof(struct) is align-multiple).
    : i total ( dbg_align_up off max_align )
    ( dbg_buffer_meta id
        ( nurl_str_cat
            ( nurl_str_cat4
                `!DICompositeType(tag: DW_TAG_structure_type, name: "`
                base `", file: !` ( nurl_str_int g_dbg_file_id ) )
            ( nurl_str_cat4
                `, size: ` ( nurl_str_int total )
                `, elements: !{` ( nurl_str_cat elems `})` ) ) ) )
    ^ id
}

// Allocate + buffer a !DISubprogram for one function. Caller stashes
// the returned id on the `define` line via `!dbg !N` and sets
// g_dbg_current_subprogram / g_dbg_current_loc so emit_dbg_eol can
// attach `!dbg` to every call/ret/br inside the body.
//   `lname` — the LLVM symbol after `@`. Usually identical to the
//             NURL source name, but `main` is rewritten to
//             `_nurl_main` (the C-side wrapper takes the bare name).
//   `line` — source line of the function header (1-based; 0 = unknown).
@ dbg_emit_subprogram s lname i line → i {
    : i sp_id ( dbg_alloc_id )
    : s ls ( nurl_str_int line )
    : s fid ( nurl_str_int g_dbg_file_id )
    : s cu  ( nurl_str_int g_dbg_cu_id )
    : s part1 ( nurl_str_cat3 `distinct !DISubprogram(name: "` lname `"` )
    : s part2 ( nurl_str_cat3 `, scope: !` fid `, file: !` )
    : s part3 ( nurl_str_cat3 fid `, line: ` ls )
    : s part4 ( nurl_str_cat3 `, scopeLine: ` ls `, unit: !` )
    : s ty  ( nurl_str_int g_dbg_subroutine_ty )
    : s body
        ( nurl_str_cat4
            part1 part2 part3
            ( nurl_str_cat4 part4 cu `, type: !`
                ( nurl_str_cat3 ty `, spFlags: DISPFlagDefinition` `)` ) ) )
    ( dbg_buffer_meta sp_id body )
    ^ sp_id
}

// Phase 5: declare a local (or function param) for gdb's `info locals`
// and `print x`. `argk` is 0 for `:` locals, 1..N for fn parameters.
// `ptr` must be a register holding the alloca pointer for `name`;
// `vt` is the LLVM type of the slot. Until Phase 6 lands, the
// DILocalVariable.type field always points at the shared
// `g_dbg_placeholder_ty` (i64); gdb still prints the value, just not
// rendered as `String` / `Vec[u]` / etc.
@ dbg_declare_local s name s ptr s vt i line i argk i syms → v {
    ? & != g_dbg_enabled 0 != g_dbg_current_subprogram 0
    {
        : i var_id ( dbg_alloc_id )
        : s sp ( nurl_str_int g_dbg_current_subprogram )
        : s fi ( nurl_str_int g_dbg_file_id )
        : s lns ( nurl_str_int line )
        : s ty_s ( nurl_str_int ( dbg_type_id_for vt syms ) )
        : s body
            ( nurl_str_cat4
                ( nurl_str_cat3 `!DILocalVariable(name: "` name `"` )
                ( nurl_str_cat3 `, arg: ` ( nurl_str_int argk ) `, scope: !` )
                ( nurl_str_cat4 sp `, file: !` fi `, line: ` )
                ( nurl_str_cat4 lns `, type: !` ty_s `)` ) )
        ( dbg_buffer_meta var_id body )
        ( nurl_print `  call void @llvm.dbg.declare(metadata ` )
        ( nurl_print vt ) ( nurl_print `* ` ) ( nurl_print ptr )
        ( nurl_print `, metadata !` ) ( nurl_print ( nurl_str_int var_id ) )
        ( nurl_print `, metadata !DIExpression())` ) ( emit_dbg_eol )
    }
    {}
}

// Allocate + buffer a !DILocation referencing the given subprogram.
// `line` is the 1-based source line; `col` is the 1-based column
// (0 = unknown). Returns the metadata id; caller assigns it to
// g_dbg_current_loc so emit_dbg_eol attaches `!dbg !N` to following
// instructions.
@ dbg_emit_location i line i col i sp_id → i {
    : i loc_id ( dbg_alloc_id )
    : s body
        ( nurl_str_cat4
            `!DILocation(line: ` ( nurl_str_int line )
            `, column: ` ( nurl_str_cat4
                ( nurl_str_int col )
                `, scope: !` ( nurl_str_int sp_id ) `)` ) )
    ( dbg_buffer_meta loc_id body )
    ^ loc_id
}

// End-of-module flush. Emits the named-metadata directives
// (`!llvm.dbg.cu`, `!llvm.module.flags`) followed by every buffered
// `!N = !DI…` definition in id order. No-op when --g is off.
@ dbg_flush → v {
    ? != g_dbg_enabled 0 {
        // Module flags — DWARF Version 4 + Debug Info Version 3 +
        // wchar_size 4. clang's default DWARF version on Linux is 4
        // and Debug Info Version 3 has been stable since LLVM 11.
        : i fv ( dbg_alloc_id )
        : i fd ( dbg_alloc_id )
        : i fw ( dbg_alloc_id )
        ( dbg_buffer_meta fv `!{i32 7, !"Dwarf Version", i32 4}` )
        ( dbg_buffer_meta fd `!{i32 2, !"Debug Info Version", i32 3}` )
        ( dbg_buffer_meta fw `!{i32 1, !"wchar_size", i32 4}` )
        ( emit `` )
        ( nurl_print `!llvm.dbg.cu = !{!` )
        ( nurl_print ( nurl_str_int g_dbg_cu_id ) )
        ( nurl_print `}\n` )
        ( nurl_print `!llvm.module.flags = !{!` )
        ( nurl_print ( nurl_str_int fv ) )
        ( nurl_print `, !` )
        ( nurl_print ( nurl_str_int fd ) )
        ( nurl_print `, !` )
        ( nurl_print ( nurl_str_int fw ) )
        ( nurl_print `}\n` )
        : ~ i mi 100
        ~ < mi g_dbg_next_id {
            : s def ( nurl_sym_get g_dbg_blob_syms ( nurl_str_int mi ) )
            ? != 0 ( nurl_str_len def )
            { ( nurl_print `!` ) ( nurl_print ( nurl_str_int mi ) )
              ( nurl_print ` = ` ) ( nurl_print def ) ( nurl_print `\n` ) }
            {}
            = mi + mi 1
        }
    } {}
}

// Phase 2B auto-drop-strings feature flag. Default ON. Compiler's own source
// uses patterns (strings stored via nurl_set_last_type, passed to nurl_lex_new,
// reassigned with = x literal) that Phase 2B string tracking can't handle
// safely, so nurlc.nu disables the pass for itself via a file-level pragma.
// See main() for the opt-out marker.
: i g_auto_drop_strings 1

// Visibility (grammar v2.0). Tracks the source-file of every @-defined
// function and per-file strict-mode opt-in.
// g_vis_syms is a nurl_sym map (handle stored as i64) with these keys:
//   __current_src_file__        — path passed to the current nurl_lex_new
//                                 (saved/restored across nested imports)
//   <fname>__src_file           — origin path of an @-defined function
//   <fname>__pub                — "1" when the @-decl was marked pub
//   <path>__strict              — "1" once any pub decl appears in <path>
// g_pending_pub is set by parse_program / scan_fn_sigs when a TT_PUB
// token is consumed; the next fn/struct/enum/const/ffi/trait/impl
// handler reads-and-clears it and records the public flag.
// Stored in nurl_sym rather than as a top-level `: s` global because
// the Python bootstrap compiler does not yet handle string globals.
: i g_pending_pub 0
: i g_vis_syms 0

@ vis_current_src_file → s {
    ^ ( nurl_sym_get g_vis_syms `__current_src_file__` )
}

@ vis_set_current_src_file s path → v {
    ( nurl_sym_def g_vis_syms `__current_src_file__` path )
}

// vis_take_pending_pub: read-and-clear g_pending_pub. Used by every
// top-level decl handler to learn whether the immediately preceding
// token stream consumed a `pub` prefix. The flag is cleared regardless
// of whether the caller cares about it, so a stray pub never sticks.
@ vis_take_pending_pub → b {
    : b was != 0 g_pending_pub
    = g_pending_pub 0
    ^ was
}

// vis_record_fn: register the source-file origin of an @-defined
// function and, if was_pub, mark it public + flip the current file
// into strict-mode. Called from gen_fn_decl (after fname is read)
// and from scan_fn_sigs's @ branch.
@ vis_record_fn s fname b was_pub → v {
    : s sf ( vis_current_src_file )
    ( nurl_sym_def g_vis_syms ( nurl_str_cat fname `__src_file` ) sf )
    ? was_pub
    { ( nurl_sym_def g_vis_syms ( nurl_str_cat fname `__pub` ) `1` )
        ( nurl_sym_def g_vis_syms ( nurl_str_cat sf `__strict` ) `1` )
    }
    {}
}

// vis_record_type: register source-file origin of a struct/enum
// declaration. `pub :` / `pub : |` marks the name itself public AND
// flips the file into strict-mode (same gate as `pub @`). Enforcement
// at the use site reads `<sname>__src_file` + `<sname>__pub` + the
// file's `__strict` marker. Mirrors vis_record_fn's shape.
@ vis_record_type s sname b was_pub → v {
    : s sf ( vis_current_src_file )
    ( nurl_sym_def g_vis_syms ( nurl_str_cat sname `__src_file` ) sf )
    ? was_pub
    { ( nurl_sym_def g_vis_syms ( nurl_str_cat sname `__pub` ) `1` )
        ( nurl_sym_def g_vis_syms ( nurl_str_cat sf `__strict` ) `1` )
    }
    {}
}

// vis_record_const: register source-file origin of a `:` global
// constant (or `: ~` mutable global). Identical bookkeeping shape
// as vis_record_type — the use site reads via the same lookup.
@ vis_record_const s cname b was_pub → v {
    : s sf ( vis_current_src_file )
    ( nurl_sym_def g_vis_syms ( nurl_str_cat cname `__src_file` ) sf )
    ? was_pub
    { ( nurl_sym_def g_vis_syms ( nurl_str_cat cname `__pub` ) `1` )
        ( nurl_sym_def g_vis_syms ( nurl_str_cat sf `__strict` ) `1` )
    }
    {}
}

// vis_check_xref: shared enforcement helper for cross-file references
// to anything tracked in g_vis_syms (@-fn, type, const, enum variant).
// `kind_label` is the human-readable noun for the diagnostic
// ("function" / "type" / "constant" / "enum variant"). Triggers `die`
// when the callee's defining file is strict AND the callee was not
// marked pub. Same shape as the gen_call check; lifted here so the
// type / const sites stay terse.
@ vis_check_xref i lex s name s kind_label → v {
    : s callee_sf ( nurl_sym_get g_vis_syms ( nurl_str_cat name `__src_file` ) )
    ? == 0 ( nurl_str_len callee_sf ) {} {
        : s here_sf ( vis_current_src_file )
        ? ( seq callee_sf here_sf ) {} {
            : s strict ( nurl_sym_get g_vis_syms ( nurl_str_cat callee_sf `__strict` ) )
            : s is_pub ( nurl_sym_get g_vis_syms ( nurl_str_cat name `__pub` ) )
            ? & ( seq strict `1` ) ! ( seq is_pub `1` )
            { ( die lex ( nurl_str_cat4
                `private ` kind_label
                ( nurl_str_cat3 ` '` name `' is not visible across files; defined in '` )
                ( nurl_str_cat callee_sf `'` ) ) ) }
            {}
        }
    }
}

@ hex_digit i d → s {
    ? == d 10 `A`
    ? == d 11 `B`
    ? == d 12 `C`
    ? == d 13 `D`
    ? == d 14 `E`
    ? == d 15 `F`
    ( nurl_str_int d )
}

@ byte_hex i c → s {
    ( nurl_str_cat ( hex_digit / c 16 ) ( hex_digit % c 16 ) )
}

@ encode_str s val i pos i end → s {
    ? >= pos end
    ``
    { : i c ( nurl_str_get val pos )
        : s esc ? | < c 32 > c 126
        ( nurl_str_cat `\` ( byte_hex c ) )
        ? | == c 34 == c 92
        ( nurl_str_cat `\` ( byte_hex c ) )
        ( nurl_str_slice val pos 1 )
        ( nurl_str_cat esc ( encode_str val + pos 1 end ) )
    }
}

@ emit_str_global i cg s val → s {
    : i idx g_str_idx
    = g_str_idx + g_str_idx 1
    : s name ( nurl_str_cat `@.str.` ( nurl_str_int idx ) )
    : i totlen + ( nurl_str_len val ) 1
    : s enc ( encode_str val 0 ( nurl_str_len val ) )
    ( nurl_print name )
    ( nurl_print ` = private unnamed_addr constant [` )
    ( nurl_print ( nurl_str_int totlen ) )
    ( nurl_print ` x i8] c"` )
    ( nurl_print enc )
    ( nurl_print `\00"\n` )
    name
}

// ── Expression generation ─────────────────────────────────────────

@ gen_int_lit i lex → s {
    : i n ( nurl_lex_inum lex )
    ( nurl_lex_advance lex )
    ( nurl_set_last_type `i64` )
    ( nurl_str_int n )
}

// gen_str_lit: emit a getelementptr referencing a deferred global constant.
// The global @.str.N is recorded in g_str_syms and emitted after each function.
@ gen_str_lit i lex i cg → s {
    : s sval ( nurl_lex_val lex )
    ( nurl_lex_advance lex )
    : i totlen + ( nurl_str_len sval ) 1
    : s enc ( encode_str sval 0 ( nurl_str_len sval ) )
    : i idx g_str_idx
    = g_str_idx + g_str_idx 1
    : s kstr ( nurl_str_int idx )
    : i sg g_str_syms
    ( nurl_sym_def sg ( nurl_str_cat `__enc_` kstr ) enc )
    ( nurl_sym_def sg ( nurl_str_cat `__len_` kstr ) ( nurl_str_int totlen ) )
    : s name ( nurl_str_cat `@.str.` kstr )
    : s res ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print res )
    ( nurl_print ` = getelementptr [` ) ( nurl_print ( nurl_str_int totlen ) )
    ( nurl_print ` x i8], [` ) ( nurl_print ( nurl_str_int totlen ) )
    ( nurl_print ` x i8]* ` ) ( nurl_print name )
    ( nurl_print `, i64 0, i64 0\n` )
    ( nurl_set_last_type `i8*` )
    res
}

@ gen_bool_lit i lex → s {
    : s bv ( nurl_lex_val lex )
    ( nurl_lex_advance lex )
    ( nurl_set_last_type `i1` )
    ? ( seq bv `T` ) `1` `0`
}

@ gen_float_lit i lex → s {
    : s fval ( nurl_lex_val lex )
    ( nurl_lex_advance lex )
    ( nurl_set_last_type `double` )
    fval
}

// gen_sizeof: Z type  →  i64 byte size of type.
// Base types return an immediate constant; struct types use the
// getelementptr-null trick to let LLVM compute the size at codegen.
@ gen_sizeof i lex i cg → s {
    ( nurl_lex_advance lex )
    : s lty ( parse_type lex )  // parse_type already returns the LLVM type
    // Known-size base types: return string constant directly
    ? ( seq lty `void` ) { ( nurl_set_last_type `i64` ) ^ `0` } {}
    ? ( seq lty `i64` ) { ( nurl_set_last_type `i64` ) ^ `8` } {}
    ? ( seq lty `double` ) { ( nurl_set_last_type `i64` ) ^ `8` } {}
    ? ( seq lty `i1` ) { ( nurl_set_last_type `i64` ) ^ `1` } {}
    // Any pointer type: last char is '*' (ASCII 42)
    ? == ( nurl_str_get lty - ( nurl_str_len lty ) 1 ) 42
    { ( nurl_set_last_type `i64` ) ^ `8` }
    {}
    // Struct / named type: getelementptr null trick
    : s r0 ( nurl_cg_reg cg )
    : s r1 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print r0 )
    ( nurl_print ` = getelementptr ` ) ( nurl_print lty )
    ( nurl_print `, ` ) ( nurl_print lty ) ( nurl_print `* null, i64 1\n` )
    ( nurl_print `  ` ) ( nurl_print r1 )
    ( nurl_print ` = ptrtoint ` ) ( nurl_print lty )
    ( nurl_print `* ` ) ( nurl_print r0 ) ( nurl_print ` to i64\n` )
    ( nurl_set_last_type `i64` )
    r1
}

@ gen_ret i lex i syms i cg → s {
    // Borrow checker: source line of the `^` token.
    : i bck_line ( nurl_lex_line lex )
    ( nurl_lex_advance lex )
    // GOTCHAS.md item 1: `^ ?? value { F e → {…} T m → {…} }` looks
    // like "return a match expression", but when ANY arm contains its
    // own `^`, the `??` becomes statement-form and yields `void`, so
    // the outer `^` has nothing to return. Snapshot whether the next
    // token is `??` so the post-gen_expr void-value diagnostic can
    // augment its message with the actual cure.
    : b returning_match == ( nurl_lex_type lex ) TT_QUESTQUEST
    // Reset __last_ident_name__ so we observe what gen_expr sets below
    ( nurl_sym_def syms `__last_ident_name__` `` )
    // Reset the escape side-channel so we can tell whether the
    // returned expression is itself a stack reference — a closure
    // literal capturing a binding by pointer (docs/GOTCHAS.md item 5).
    ( nurl_sym_def syms `__last_expr_refdepth__` `` )
    // Tail-call optimisation: mark the upcoming expression as
    // "tail-position" so gen_call can emit `tail call` (the LLVM
    // optimiser then converts a self-recursive tail call into a jump,
    // unblocking deep recursion). The flag is consumed BY gen_call as
    // soon as it enters — argument evaluation happens AFTER the
    // consume, so nested calls inside the argument list do NOT
    // observe the flag and stay non-tail. Eligibility is re-checked
    // in gen_call (matching return types, no closure / FFI dispatch
    // shape, no variadic). The flag is ONLY set when there are no
    // pending owned-resource drops to perform after the call: an
    // owned-slice / owned-string / user-drop in scope would emit
    // extra calls between the tail-call and `ret`, which LLVM would
    // silently degrade. defer chains likewise force a non-tail call.
    ? & & & ( seq ( nurl_sym_get syms `__owned_strings__` ) `` )
             ( seq ( nurl_sym_get syms `__owned_slices__` ) `` )
             ( seq ( nurl_sym_get syms `__owned_struct_fields__` ) `` )
        & ( seq ( nurl_sym_get syms `__user_drops__` ) `` )
          ( seq ( nurl_sym_get syms `__defer_top__` ) `` )
    { ( nurl_sym_def syms `__tail_call_pending__` `1` ) }
    {}
    : s val ( gen_expr lex syms cg )
    // Borrow checker: record this return statement.
    ( bck_record `ret` `` bck_line )
    // Defensive: clear any residual pending flag (gen_expr may have
    // taken a different path — e.g. a literal or operator — that
    // never reached gen_call to consume it).
    ( nurl_sym_def syms `__tail_call_pending__` `` )
    : s lt ( nurl_get_last_type )
    // Escape analysis (BORROW.md Phase 3): warn if the returned value
    // is a stack reference — a closure capturing a binding by pointer,
    // an aggregate holding one, or a binding holding either. The
    // referent is a local / parameter of THIS function, so returning
    // it past the function frame always dangles. Covers the bare
    // closure literal (`^ \ → v { ... c ... }`), the bound closure
    // (`^ binding`), and the struct wrapper (`^ @ Slot { cb }`)
    // uniformly. Only consulted when --borrowck is on.
    ( bck_esc_check_return lex syms bck_line
        ( nurl_sym_get syms `__last_ident_name__` ) )
    // Diagnose cases where gen_expr produced no usable value (last_type =
    // void, e.g. a `? cond then else` whose two arms have incompatible
    // types so gen_cond degrades silently to void) while the function
    // expects a real return value. Without this, gen_ret would emit
    // `ret void` from an i64-returning function and LLVM would reject it
    // downstream with the cryptic "value doesn't match function result
    // type" error.
    : s fn_rt ( nurl_sym_get syms `__fn_ret_ty__` )
    ? & & ( seq lt `void` ) != 0 ( nurl_str_len fn_rt ) ! ( seq fn_rt `void` )
    { : s hint ? returning_match
        `) — match arms contain '^' so '?? …' is statement-form, not an expression. Refactor to ': ~ T rc init / ?? mr { … = rc v } / ^ rc'. See docs/GOTCHAS.md item 6.`
        `) — likely a conditional with incompatible branch types`
        ( die lex ( nurl_str_cat `return expression has no value (expected `
            ( nurl_str_cat ( llvm_to_nurl fn_rt ) hint ) ) ) }
    {}
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    // Determine which owned-slice binding (if any) is escaping as the return value.
    // Ownership transfers only when the return type is itself a slice AND the
    // returned expression resolved to a simple identifier load.
    : s ret_ident ( nurl_sym_get syms `__last_ident_name__` )
    : s skip ? & ( mem_is_slice_ty lt ) ( str_contains_word ( nurl_sym_get syms `__owned_slices__` ) ret_ident )
    ret_ident
    ``
    // Phase 2B: owned-string escape analysis on the returned identifier.
    : s skip_str_ptr ``
    : s skip_user_ptr ``
    ? != 0 g_auto_drop_strings
    { : s rid_ptr ( nurl_sym_get syms ( nurl_str_cat ret_ident `__ptr` ) )
        = skip_str_ptr ? & ( seq lt `i8*` ) ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) rid_ptr )
        rid_ptr
        ``
        ? != 0 ( nurl_str_len skip_str_ptr )
        { ( nurl_sym_def syms `__fn_ret_str_owned__` `1` ) }
        {}
        = skip_user_ptr ? ( str_contains_word ( nurl_sym_get syms `__user_drops__` ) rid_ptr )
        rid_ptr
        ``
    }
    {}
    ? != 0 ( nurl_str_len skip )
    { ( nurl_sym_def syms `__fn_ret_owned__` `1` ) }
    {}
    ? != 0 ( nurl_str_len dtop )
    {  // defers active: store return value then branch to defer chain
        ? ! ( seq lt `void` )
        { : s rvp ( nurl_sym_get syms `__ret_val__` )
            ( nurl_print `  store ` ) ( nurl_print lt ) ( nurl_print ` ` )
            ( nurl_print val ) ( nurl_print `, ` ) ( nurl_print lt )
            ( nurl_print `* ` ) ( nurl_print rvp ) ( nurl_print `\n` )
        }
        {}
        ( nurl_print `  br label %` ) ( nurl_print dtop ) ( emit_dbg_eol )
    }
    {  // no defers: drop owned slices then direct return
        ( mem_drop_owned syms cg skip )
        ? != 0 g_auto_drop_strings
        { ( mem_drop_owned_strings syms cg skip_str_ptr )
            ( mem_drop_owned_struct_fields syms cg )
            ( mem_drop_user_drops syms cg skip_user_ptr )
        }
        {}
        ? ( seq lt `void` )
        { ( emit_call_term `ret void` ) }
        { ( nurl_print `  ret ` ) ( nurl_print lt )
            ( nurl_print ` ` ) ( nurl_print val ) ( emit_dbg_eol ) }
    }
    ( nurl_set_last_type `void` )
    = g_did_ret 1
    val
}

@ gen_unary_not i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s v ( gen_expr lex syms cg )
    : s res ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print res )
    ( nurl_print ` = xor i1 ` ) ( nurl_print v ) ( nurl_print `, 1\n` )
    ( nurl_set_last_type `i1` )
    res
}

// is_binop_tt: true if tt is a binary arithmetic/comparison operator token.
@ is_binop_tt i tt → b {
    | | & >= tt TT_PLUS <= tt TT_PIPE
    | == tt TT_LT | == tt TT_GT | == tt TT_EQEQ | == tt TT_NE | == tt TT_LE == tt TT_GE
    | | == tt TT_SHL == tt TT_SHR == tt TT_CARETCARET
}

// g_stmt_line — source line of the statement gen_stmt is currently
// parsing. Read by gen_ident's "unexpected token" diagnostic: when an
// operand parse over-reads past its statement (a prefix operator short
// an argument — the classic NURL arity cascade), the offending token
// lands on a LATER line than this, which lets the error point back at
// the real culprit instead of blaming the innocent next statement.
: i g_stmt_line 0

// __tok_label — a human-readable name for a token that turned up where
// a value expression was required. Used only on the diagnostic path.
@ __tok_label i tt s val → s {
    ? == tt TT_COLON   { ^ `':' (a ':' binding starts here)` } {}
    ? == tt TT_EQ      { ^ `'=' (an assignment starts here)` } {}
    ? == tt TT_SEMICOL { ^ `';' (a ';' defer starts here)` } {}
    ? == tt TT_RBRACE  { ^ `'}' (the enclosing block ends here)` } {}
    ? == tt TT_RPAREN  { ^ `')'` } {}
    ? == tt TT_RBRACK  { ^ `']'` } {}
    ? == tt TT_EOF     { ^ `end of input` } {}
    ? == tt TT_ARROW   { ^ `'->'` } {}
    ? != 0 ( nurl_str_len val ) { ^ ( nurl_str_cat3 `'` val `'` ) } {}
    `this token`
}

@ gen_expr i lex i syms i cg → s {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_INT ( gen_int_lit lex )
    ? == tt TT_FLOAT ( gen_float_lit lex )
    ? == tt TT_STR ( gen_str_lit lex cg )
    ? == tt TT_BOOL ( gen_bool_lit lex )
    ? == tt TT_SIZEOF ( gen_sizeof lex cg )
    ? == tt TT_CARET ( gen_ret lex syms cg )
    ? == tt TT_BANG ( gen_unary_not lex syms cg )
    ? == tt TT_QUEST ( gen_cond lex syms cg )
    ? == tt TT_QUESTQUEST ( gen_match lex syms cg )
    ? == tt TT_LBRACE ( gen_block_expr lex syms cg )
    ? == tt TT_LPAREN ( gen_call lex syms cg )
    ? == tt TT_HASH ( gen_cast lex syms cg )
    ? == tt TT_DOT ( gen_member lex syms cg )
    ? == tt TT_AT ( gen_agg_lit lex syms cg )
    ? == tt TT_BACKSLASH ( gen_backslash_expr lex syms cg )
    ? == tt TT_LBRACK ( gen_slice_literal lex syms cg )
    ? == tt TT_OROR ( gen_oror lex syms cg )
    ? == tt TT_ANDAND ( gen_andand lex syms cg )
    ? ( is_binop_tt tt ) ( gen_binary lex syms cg )
    ? == tt TT_TILDE ( gen_complement lex syms cg )
    ( gen_ident lex syms cg )
}

// ── `||` / `&&` — strict binary short-circuit (bool only) ─────────────
// Unlike `|` / `&` (which dispatch to bitwise vs short-circuit based on
// operand type and chain N+1 operands per N tokens), the two-char
// variants are fixed arity 2 and require both operands to be bool.
// Useful when a chain like `( cond1 || cond2 || cond3 )` would be more
// readable than the canonical `| | cond1 cond2 cond3`. The compiled
// IR is identical to gen_logical_or / gen_logical_and's i1 path.
@ gen_oror i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s lv ( gen_expr lex syms cg )
    : s lt ( nurl_get_last_type )
    ? ! ( seq lt `i1` )
    { ( die lex `operator || requires bool operands — left operand has non-bool type` ) }
    {}
    : s left_lbl ( nurl_sym_get syms `__cur_lbl__` )
    ^ ( gen_logical_or lv left_lbl lex syms cg )
}

@ gen_andand i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s lv ( gen_expr lex syms cg )
    : s lt ( nurl_get_last_type )
    ? ! ( seq lt `i1` )
    { ( die lex `operator && requires bool operands — left operand has non-bool type` ) }
    {}
    : s left_lbl ( nurl_sym_get syms `__cur_lbl__` )
    ^ ( gen_logical_and lv left_lbl lex syms cg )
}

@ gen_complement i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s v ( gen_expr lex syms cg )
    : s lt ( nurl_get_last_type )
    : s res ( nurl_cg_reg cg )
    ? ( seq lt `double` )
    { ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ` = fneg double ` ) ( nurl_print v ) ( nurl_print `\n` )
    }
    { ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ` = xor ` ) ( nurl_print lt )
        ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `, -1\n` )
    }
    res
}

// load_var: emit a load instruction and return the result register.
@ load_var i cg s lt s ptr → s {
    : s res ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print res )
    ( nurl_print ` = load ` ) ( nurl_print lt )
    ( nurl_print `, ` ) ( nurl_print lt )
    ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
    res
}

@ gen_ident i lex i syms i cg → s {
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s name ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        // Borrow checker: every value-position identifier is a read.
        ( bck_note_read name )
        : s lt ( nurl_sym_get syms name )
        ( nurl_set_last_type ? == 0 ( nurl_str_len lt ) `i64` lt )
        : s ptr ( nurl_sym_get syms ( nurl_str_cat name `__ptr` ) )
        : s glb ( nurl_sym_get syms ( nurl_str_cat name `__global` ) )
        // GOTCHAS.md item 11: bare `@-fn` names don't auto-coerce to a
        // `(@ R P*)` closure parameter. A bare @-fn ident used as a
        // value (i.e. NOT as a call's callee — gen_call's own path
        // consumes the name before reaching here) currently emits IR
        // that clang rejects with `use of undefined value '%name'`,
        // because nurlc's fallback returns `%name` rather than a
        // closure struct. Detect: name has `__src_file` set (i.e. is
        // a @-fn) AND no `__ptr` (not a local) AND no `__global`
        // (not a const / enum variant). Die with the canonical
        // wrap-in-closure-literal cure.
        ? & & == 0 ( nurl_str_len ptr ) == 0 ( nurl_str_len glb ) != 0 ( nurl_str_len ( nurl_sym_get g_vis_syms ( nurl_str_cat name `__src_file` ) ) )
        { : s tail ( nurl_str_cat name ` args ) }'. See docs/GOTCHAS.md item 11.` )
            ( die lex ( nurl_str_cat4
                `bare '@-fn' name '` name
                `' does not auto-coerce to a closure value. Wrap it: '\ args → R { ( `
                tail ) ) }
        {}
        // Cross-file visibility check for globals (consts + enum
        // variants). Locals have a `__ptr` entry and skip this entirely
        // — the strict-mode rule is global-symbol-only. The check is a
        // no-op for same-file references and for builtins whose
        // __src_file is unset.
        ? != 0 ( nurl_str_len glb )
        { ( vis_check_xref lex name `global` ) }
        {}
        ( nurl_sym_def syms `__last_ident_name__` name )
        // Propagate the binding's unsigned-ness as a side-channel so
        // downstream casts / stores can choose sext vs zext correctly.
        // Empty when the binding wasn't tagged (literals, struct fields,
        // function returns — Phase 1A defaults those to signed).
        : s u_flag ( nurl_sym_get syms ( nurl_str_cat name `__unsigned` ) )
        ( nurl_sym_def syms `__last_unsigned__` u_flag )
        ^ ? != 0 ( nurl_str_len ptr )
        ( load_var cg lt ptr )
        ? != 0 ( nurl_str_len glb )
        ( load_var cg lt ( nurl_str_cat `@` name ) )
        ( nurl_str_cat `%` name )
    }
    { : i ut ( nurl_lex_type lex )
        : i uln ( nurl_lex_line lex )
        : s un ( __tok_label ut ( nurl_lex_val lex ) )
        // A closer / statement-starter cannot begin a value expression.
        // Reaching one here means a prefix operator on a preceding line
        // ran out of operands and over-read into the next statement —
        // the classic NURL arity cascade. Name the token and, when it
        // sits past the current statement's start line, point back at
        // the real culprit instead of blaming this innocent line.
        : b blocks_value | | | | == ut TT_COLON == ut TT_EQ == ut TT_SEMICOL
            == ut TT_RBRACE | == ut TT_EOF | == ut TT_RPAREN == ut TT_RBRACK
        ? blocks_value
        { : s where ? > uln g_stmt_line
            ( nurl_str_cat3 ` the statement starting at line ` ( nurl_str_int g_stmt_line ) ` is still being parsed, so` )
            ``
          ( die lex ( nurl_str_cat3
            ( nurl_str_cat3 `unexpected ` un ` where a value expression is required —` )
            where
            ` a prefix operator is short an argument: every NURL operator has fixed arity and no closing bracket, so a missing operand silently consumes whatever follows. See README -> Known Limitations -> Grammar.` ) ) }
        { ( die lex ( nurl_str_cat3 `unexpected ` un ` in expression` ) ) } }
}

// ── Binary op OP lhs rhs ─────────────────────────────────────────

@ gen_binary i lex i syms i cg → s {
    : i tt ( nurl_lex_type lex )
    // Handle logical vs bitwise & and | operators
    ? == tt TT_AMP ^ ( gen_logical_or_bitwise_and lex syms cg )
    ? == tt TT_PIPE ^ ( gen_logical_or_bitwise_or lex syms cg )
    // Original binary operation logic for other operators
    ( nurl_lex_advance lex )
    // Phase 1B signedness propagation: `gen_ident` writes the loaded
    // binding's `__unsigned` flag into `__last_unsigned__` so binops can
    // pick `udiv`/`urem`/`lshr`/`icmp u*` over their signed equivalents
    // when an operand was declared as a sized unsigned type (u16/u32/u64,
    // or legacy `u` → i8). Clear the marker before LHS so a literal-LHS
    // expression doesn't inherit stale state from a prior load.
    ( nurl_sym_def syms `__last_unsigned__` `` )
    : s lv ( gen_expr lex syms cg )
    : s lt ( nurl_get_last_type )
    : s lu_snap ( nurl_sym_get syms `__last_unsigned__` )
    ( nurl_sym_def syms `__last_unsigned__` `` )
    : s rv ( gen_expr lex syms cg )
    : s ru_snap ( nurl_sym_get syms `__last_unsigned__` )
    : s res ( nurl_cg_reg cg )
    : b isf | ( seq lt `double` ) ( seq lt `float` )
    // `^^` (XOR) is integer/bool-only — LLVM has no float `xor`.
    ? & == tt TT_CARETCARET isf
    { ( die lex `operator '^^' (XOR) requires integer or bool operands, not a float` ) }
    {}
    // Unsigned operand path. Three triggers, OR-ed:
    //   * Legacy 8-bit byte (`u` → i8): retained for v1.6 compatibility.
    //   * Either operand carries the `__unsigned` flag (sized u types).
    // NURL is strongly typed (no implicit conversions), so lt == rt
    // always holds for arithmetic operands — the OR over both operands'
    // flags is defensive against asymmetric loss along complex paths
    // rather than meaningful signedness coercion.
    : b isu | | ( seq lt `i8` ) != 0 ( nurl_str_len lu_snap )
    != 0 ( nurl_str_len ru_snap )
    : s ins ( binop_instr tt isf isu )
    ( nurl_print `  ` ) ( nurl_print res ) ( nurl_print ` = ` )
    ( nurl_print ins ) ( nurl_print ` ` )
    ( nurl_print lt ) ( nurl_print ` ` )
    ( nurl_print lv ) ( nurl_print `, ` ) ( nurl_print rv ) ( nurl_print `\n` )
    ? | & >= tt TT_LT <= tt TT_GE | == tt TT_EQEQ == tt TT_NE
    ( nurl_set_last_type `i1` )
    ( nurl_set_last_type lt )
    // Propagate the result's signedness so a nested binop ( + a + b c )
    // emits the right ops for the outer +.
    ( nurl_sym_def syms `__last_unsigned__` ? isu `1` `` )
    res
}

// ── Logical AND with short-circuit ───────────────────────────────────
@ gen_logical_and s lv s left_lbl i lex i syms i cg → s {
    : s lright ( nurl_cg_lbl cg `and_right` )
    : s lend ( nurl_cg_lbl cg `and_end` )
    // Short-circuit: if left is false, skip right evaluation
    ( nurl_print `  br i1 ` ) ( nurl_print lv )
    ( nurl_print `, label %` ) ( nurl_print lright )
    ( nurl_print `, label %` ) ( nurl_print lend ) ( emit_dbg_eol )
    // Right branch: evaluate right operand
    ( emit ( nurl_str_cat lright `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lright )
    : s rv ( gen_expr lex syms cg )
    : s rt ( nurl_get_last_type )
    // Check type compatibility
    ? ! ( seq rt `i1` )
    ( die lex `operator & requires matching types — right operand must be b` )
    {}
    : s right_lbl ( nurl_sym_get syms `__cur_lbl__` )
    ( nurl_print `  br label %` ) ( nurl_print lend ) ( emit_dbg_eol )
    // End: phi node to select result
    ( emit ( nurl_str_cat lend `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lend )
    : s res ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print res )
    ( nurl_print ` = phi i1 [ 0, %` ) ( nurl_print left_lbl )
    ( nurl_print ` ], [ ` ) ( nurl_print rv ) ( nurl_print `, %` ) ( nurl_print right_lbl )
    ( nurl_print ` ]\n` )
    ( nurl_set_last_type `i1` )
    res
}

// ── Logical OR with short-circuit ────────────────────────────────────
@ gen_logical_or s lv s left_lbl i lex i syms i cg → s {
    : s lright ( nurl_cg_lbl cg `or_right` )
    : s lend ( nurl_cg_lbl cg `or_end` )
    // Short-circuit: if left is true, skip right evaluation
    ( nurl_print `  br i1 ` ) ( nurl_print lv )
    ( nurl_print `, label %` ) ( nurl_print lend )
    ( nurl_print `, label %` ) ( nurl_print lright ) ( emit_dbg_eol )
    // Right branch: evaluate right operand
    ( emit ( nurl_str_cat lright `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lright )
    : s rv ( gen_expr lex syms cg )
    : s rt ( nurl_get_last_type )
    // Check type compatibility
    ? ! ( seq rt `i1` )
    ( die lex `operator | requires matching types — right operand must be b` )
    {}
    : s right_lbl ( nurl_sym_get syms `__cur_lbl__` )
    ( nurl_print `  br label %` ) ( nurl_print lend ) ( emit_dbg_eol )
    // End: phi node to select result
    ( emit ( nurl_str_cat lend `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lend )
    : s res ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print res )
    ( nurl_print ` = phi i1 [ 1, %` ) ( nurl_print left_lbl )
    ( nurl_print ` ], [ ` ) ( nurl_print rv ) ( nurl_print `, %` ) ( nurl_print right_lbl )
    ( nurl_print ` ]\n` )
    ( nurl_set_last_type `i1` )
    res
}

// ── Bitwise operations for integers ──────────────────────────────────
@ gen_bitwise_binary s lv s lt i lex i syms i cg i tt → s {
    : s rv ( gen_expr lex syms cg )
    : s rt ( nurl_get_last_type )
    // Check type compatibility
    ? ! ( seq lt rt )
    { : s op_name ? == tt TT_AMP `&` `|`
        : s msg1 ( nurl_str_cat `operator ` ( nurl_str_cat op_name ` requires matching types — got ` ) )
        : s msg2 ( nurl_str_cat ( llvm_to_nurl lt ) ( nurl_str_cat ` and ` ( llvm_to_nurl rt ) ) )
        ( die lex ( nurl_str_cat msg1 msg2 ) )
    }
    {}
    : s res ( nurl_cg_reg cg )
    : b isf | ( seq lt `double` ) ( seq lt `float` )
    : b isu ( seq lt `i8` )
    : s ins ( binop_instr tt isf isu )
    ( nurl_print `  ` ) ( nurl_print res ) ( nurl_print ` = ` )
    ( nurl_print ins ) ( nurl_print ` ` )
    ( nurl_print lt ) ( nurl_print ` ` )
    ( nurl_print lv ) ( nurl_print `, ` ) ( nurl_print rv ) ( nurl_print `\n` )
    ( nurl_set_last_type lt )
    res
}

// ── Type-based dispatch for & and | ──────────────────────────────────
@ gen_logical_or_bitwise_and i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s lv ( gen_expr lex syms cg )
    : s lt ( nurl_get_last_type )
    : s left_lbl ( nurl_sym_get syms `__cur_lbl__` )
    // Determine operation type based on left operand type.
    // i1 → short-circuit boolean AND.
    // Any integer width (i8/i16/i32/i64) → bitwise AND. `and` and `or`
    // are sign-agnostic LLVM ops, so unsigned operands take the same
    // path and `gen_bitwise_binary` doesn't need a signedness flag.
    ? ( seq lt `i1` )
    { ^ ( gen_logical_and lv left_lbl lex syms cg ) }
    { ? > ( int_width lt ) 0
        { ^ ( gen_bitwise_binary lv lt lex syms cg TT_AMP ) }
        { : s msg ( nurl_str_cat `operator & requires matching types — got ` ( llvm_to_nurl lt ) )
            ( die lex ( nurl_str_cat msg ` and unknown` ) )
            ^ `error`
        }
    }
}

@ gen_logical_or_bitwise_or i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s lv ( gen_expr lex syms cg )
    : s lt ( nurl_get_last_type )
    : s left_lbl ( nurl_sym_get syms `__cur_lbl__` )
    // i1 → short-circuit boolean OR; any integer width → bitwise OR.
    ? ( seq lt `i1` )
    { ^ ( gen_logical_or lv left_lbl lex syms cg ) }
    { ? > ( int_width lt ) 0
        { ^ ( gen_bitwise_binary lv lt lex syms cg TT_PIPE ) }
        { : s msg ( nurl_str_cat `operator | requires matching types — got ` ( llvm_to_nurl lt ) )
            ( die lex ( nurl_str_cat msg ` and unknown` ) )
            ^ `error`
        }
    }
}

// `isu` = unsigned-operand path: selects unsigned compare predicates,
// logical (zero-fill) shift right, and unsigned div/rem. Set when
// either operand is a sized unsigned type (`u`/`u16`/`u32`/`u64`)
// via the `__last_unsigned__` side-channel propagated by `gen_ident`
// and `gen_binary`. Equality predicates (`==`, `!=`) are sign-
// agnostic, so they take the signed entry. `add`/`sub`/`mul`/`and`/
// `or` produce identical results on signed and unsigned operands of
// the same width, so they're keyed off `isf` only.
@ binop_instr i tt b isf b isu → s {
    ? == tt TT_PLUS ? isf `fadd` `add`
    ? == tt TT_MINUS ? isf `fsub` `sub`
    ? == tt TT_STAR ? isf `fmul` `mul`
    ? == tt TT_SLASH ? isf `fdiv` ? isu `udiv` `sdiv`
    ? == tt TT_PERCENT ? isf `frem` ? isu `urem` `srem`
    ? == tt TT_AMP `and`
    ? == tt TT_PIPE `or`
    ? == tt TT_CARETCARET `xor`
    ? == tt TT_SHL `shl`
    ? == tt TT_SHR ? isu `lshr` `ashr`
    ? == tt TT_LT ? isf `fcmp olt` ? isu `icmp ult` `icmp slt`
    ? == tt TT_GT ? isf `fcmp ogt` ? isu `icmp ugt` `icmp sgt`
    ? == tt TT_EQEQ ? isf `fcmp oeq` `icmp eq`
    ? == tt TT_NE ? isf `fcmp one` `icmp ne`
    ? == tt TT_LE ? isf `fcmp ole` ? isu `icmp ule` `icmp sle`
    ? == tt TT_GE ? isf `fcmp oge` ? isu `icmp uge` `icmp sge`
    `add`
}

// ── Call ( fn args... ) ───────────────────────────────────────────

// Call a closure function pointer (closure struct with function + environment)
@ call_closure_function s closure_var s closure_type s argstr i cg → s {
    : s ret_type ( extract_fn_ptr_return_type closure_type )

    // Extract function pointer from closure struct (field 0)
    : s fn_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print fn_ptr )
    ( nurl_print ` = extractvalue ` ) ( nurl_print closure_type ) ( nurl_print ` ` ) ( nurl_print closure_var )
    ( nurl_print `, 0\n` )

    // Extract environment pointer from closure struct (field 1)
    : s env_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print env_ptr )
    ( nurl_print ` = extractvalue ` ) ( nurl_print closure_type ) ( nurl_print ` ` ) ( nurl_print closure_var )
    ( nurl_print `, 1\n` )

    // Call the function pointer with environment as first argument.
    // For void return, LLVM forbids `%rN = call void ...` (void instr can't
    // be named) — emit the unnamed form and return env_ptr as a placeholder
    // value (callers of void calls don't read the result).
    : b void_ret != 0 ( nurl_str_eq ret_type `void` )
    : s res ? void_ret env_ptr ( nurl_cg_reg cg )
    ? void_ret
    { ( nurl_print `  call void ` ) ( nurl_print fn_ptr ) }
    { ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ` = call ` ) ( nurl_print ret_type ) ( nurl_print ` ` ) ( nurl_print fn_ptr ) }
    ( nurl_print `(i8* ` ) ( nurl_print env_ptr )

    // Add other arguments if any
    ? != 0 ( nurl_str_len argstr )
    { ( nurl_print `, ` ) ( nurl_print argstr ) }
    {}

    ( nurl_print `)\n` )
    ( nurl_set_last_type ret_type )
    res
}

// Extract return type from function pointer type
// e.g., "i64 (i64)*" → "i64", "void (i8*)*" → "void"
@ extract_fn_ptr_return_type s fn_ptr_type → s {
    // Simple parsing for function pointer types like "i64 (i64)*" or "void ()*"
    // or closure struct types like "{ i64 (i8*)*, i8* }"
    : i len ( nurl_str_len fn_ptr_type )
    : i start_pos 0
    // Skip leading "{ " for closure struct types
    ? & >= len 2 == ( nurl_str_get fn_ptr_type 0 ) 123 { = start_pos 2 } {}

    : b contains_space_paren F
    : i i start_pos
    ~ < i - len 1 {
        ? & == ( nurl_str_get fn_ptr_type i ) 32  // space character
        == ( nurl_str_get fn_ptr_type + i 1 ) 40  // '(' character
        { = contains_space_paren T }
        {}
        = i + i 1
    }
    ? contains_space_paren
    {
        // Find the top-level space separating return type from param list.
        // Must track brace depth: for nested struct returns like
        // `{ { i1, i64 } (i8*, i64)*, i8* }`, the first raw space sits inside
        // the inner `{}` and must be skipped.
        : i space_idx start_pos
        : i depth 0
        ~ < space_idx len {
            : i ch ( nurl_str_get fn_ptr_type space_idx )
            ? == ch 123 { = depth + depth 1 } {}  // '{' deeper
            ? == ch 125 { = depth - depth 1 } {}  // '}' shallower
            ? & == ch 32 == depth 0  // space at top level
            { ^ ( nurl_str_slice fn_ptr_type start_pos - space_idx start_pos ) }
            {}
            = space_idx + space_idx 1
        }
        fn_ptr_type  // fallback
    }
    { fn_ptr_type }  // Not a function pointer, return as-is
}

// ── Variadic FFI: C default argument promotions ──────────────────
// When calling a variadic function, the C ABI requires that any
// argument passed through the `...` undergoes "default argument
// promotion": `float` widens to `double`, and any integer narrower
// than `int` (i.e. `_Bool` / `char` / `short`) widens to `int`
// (LLVM `i32` on every triple NURL currently targets). LLVM IR does
// not auto-promote at the call site — we emit explicit `fpext` /
// `sext` / `zext` for the variadic-position args here.
//
// Signedness of narrow ints comes from the `__last_unsigned__`
// side-channel that `gen_ident` writes from the binding's
// `__unsigned` flag (Phase 1B). For values that did not flow through
// an ident load — call results, literals, arithmetic with mixed
// signedness — `lu` is empty and we fall back to `sext`, matching the
// signed-int default the grammar already applies elsewhere.

@ variadic_promoted_type s at → s {
    ? ( seq at `float` ) { ^ `double` } {}
    ? ( seq at `i1` ) { ^ `i32` } {}
    ? ( seq at `i8` ) { ^ `i32` } {}
    ? ( seq at `i16` ) { ^ `i32` } {}
    at
}

@ variadic_promote_arg i cg s at s av s lu → s {
    ? ( seq at `float` )
    { : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = fpext float ` ) ( nurl_print av )
        ( nurl_print ` to double\n` )
        ^ r }
    {}
    ? ( seq at `i1` )
    { : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = zext i1 ` ) ( nurl_print av )
        ( nurl_print ` to i32\n` )
        ^ r }
    {}
    ? | ( seq at `i8` ) ( seq at `i16` )
    { : s inst ? != 0 ( nurl_str_len lu ) `zext` `sext`
        : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = ` ) ( nurl_print inst )
        ( nurl_print ` ` ) ( nurl_print at )
        ( nurl_print ` ` ) ( nurl_print av )
        ( nurl_print ` to i32\n` )
        ^ r }
    {}
    av
}

// Emit `call void @nurl_free(i8* %r)` for every register in `temps`
// (space-separated). Called by gen_call after a callee returns to release
// owned-string argument temporaries (Phase 2B parameter-ownership).
@ mem_drop_arg_temps s temps → v {
    : s rest temps
    ~ != 0 ( nurl_str_len rest ) {
        : s reg ( str_first_word rest )
        = rest ( str_skip_word rest )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print reg ) ( nurl_print `)` ) ( emit_dbg_eol )
    }
}

// gen_inout_field_addr: lex is positioned at the TT_DOT of an
// `inout . obj field` call argument. Emits a `getelementptr` to the
// named field of the struct binding `obj` and returns that
// field-pointer register, with the last-type side-channel set to
// `<fieldtype>*` so gen_call passes it as the `inout` pointer.
//
// `obj` must be a bare mutable (`: ~`) struct binding — or an `inout`
// struct parameter, which carries the same `__ptr` / `__mutable`
// shape. Single-level access only (`. obj field`); `.` is dyadic so
// the argument is exactly three tokens and the next token always
// begins the following argument. The field-name → index / type
// lookup uses the `<sname>__<field>__idx` / `__type` entries
// gen_struct_decl (and the generic-instantiation emitter) register
// for every struct, so this works for plain and generic structs.
@ gen_inout_field_addr i lex i syms i cg s fname → s {
    ( nurl_lex_advance lex )  // consume '.'
    ? ! ( is_ident_tok ( nurl_lex_type lex ) )
    { ( die lex ( nurl_str_cat3
        `inout field argument to '` fname
        `' must be '. <binding> <field>' naming a plain struct binding` ) ) }
    {}
    : s obj ( nurl_lex_val lex )
    ( nurl_lex_advance lex )
    : s objptr ( nurl_sym_get syms ( nurl_str_cat obj `__ptr` ) )
    : s objty ( nurl_sym_get syms obj )
    ? == 0 ( nurl_str_len objptr )
    { ( die lex ( nurl_str_cat3
        `inout field argument: '` obj `' is not a struct binding in scope` ) ) }
    {}
    ? == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat obj `__mutable` ) ) )
    { ( die lex ( nurl_str_cat3
        `inout field argument: binding '` obj
        `' must be mutable ': ~' - the callee mutates its field in place` ) ) }
    {}
    ? | == 0 ( nurl_str_len objty ) ! == 37 ( nurl_str_get objty 0 )
    { ( die lex ( nurl_str_cat3
        `inout field argument: '` obj `' is not a named-struct binding` ) ) }
    {}
    ? ! ( is_ident_tok ( nurl_lex_type lex ) )
    { ( die lex ( nurl_str_cat3
        `inout field argument: expected a field name after '. ` obj `'` ) ) }
    {}
    : s fld ( nurl_lex_val lex )
    ( nurl_lex_advance lex )
    : s sname ( nurl_str_slice objty 1 - ( nurl_str_len objty ) 1 )
    : s idx_s ( nurl_sym_get syms
        ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fld `__idx` ) ) ) )
    : s fty ( nurl_sym_get syms
        ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fld `__type` ) ) ) )
    ? == 0 ( nurl_str_len idx_s )
    { ( die lex ( nurl_str_cat4
        `inout field argument: struct '` sname `' has no field '` fld ) ) }
    {}
    : s gep ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print gep )
    ( nurl_print ` = getelementptr ` ) ( nurl_print objty )
    ( nurl_print `, ` ) ( nurl_print objty ) ( nurl_print `* ` ) ( nurl_print objptr )
    ( nurl_print `, i32 0, i32 ` ) ( nurl_print idx_s ) ( nurl_print `\n` )
    ( nurl_set_last_type ( nurl_str_cat fty `*` ) )
    ^ gep
}

// A '(' begins a function call, so the token right after it must be a
// function name. An operator token there (`.` `|` `&` `+` `==` …) means
// an operator expression was wrongly wrapped in parentheses — the
// classic NURL trap `( . obj field )` written for `. obj field`. Left
// alone, gen_call takes the operator's lexeme as the callee name and
// emits a call to a function literally named `.`, which links nowhere:
// the failure surfaces far from the source as `use of undefined value`.
// gen_call catches it at the call site instead. The set is the binary
// operators plus member access `.`, the cast `#` and the caret `^` —
// every token here is unambiguously an operator, never a function name.
// Identifier-continuation predicate — used by scan helpers below.
// Inlines the ASCII alpha/digit/underscore check; the historic
// `nurl_is_alpha` / `_is_digit` C helpers were dropped in
// PURIFY.md Phase 1 (2026-05-23) and the nurlc compiler is
// self-contained (no `$`-imports) so the check lives here verbatim.
@ __is_ident_char i ch → b {
    ^ | | | & >= ch 65 <= ch 90 & >= ch 97 <= ch 122 & >= ch 48 <= ch 57 == ch 95
}

// Pure-NURL replacements for the historic `nurl_str_*` C wrappers
// in `stdlib/runtime.c §2` (PURIFY.md Phase 5, 2026-05-23). Each
// is mirrored in `stdlib/core/string.nu` for user code; the
// duplication is because `nurlc.nu` has no `$`-imports — the
// linker sees only this local copy in the nurlc binary, only the
// stdlib copy in user binaries.

@ nurl_memcmp_lex s a i la s b i lb → i {
    : i n ? < la lb la lb
    ? > n 0 {
        : i c # i ( memcmp a b n )
        ? != c 0 { ^ ? < c 0 -1 1 } {}
    } {}
    ? < la lb { ^ -1 } {}
    ? > la lb { ^ 1 } {}
    ^ 0
}

@ nurl_str_len s str → i {
    ^ ( strlen str )
}

@ nurl_str_eq s a s b → i {
    : i c # i ( strcmp a b )
    ^ ? == c 0 1 0
}

@ nurl_str_cmp s a s b → i {
    : i c # i ( strcmp a b )
    ? < c 0 { ^ -1 } {}
    ? > c 0 { ^ 1 } {}
    ^ 0
}

@ nurl_str_to_int s str → i {
    ^ ( atoll str )
}

@ nurl_str_to_float s str → f {
    ^ ( atof str )
}

@ nurl_str_starts s str s prefix → i {
    : i n ( strlen prefix )
    : i c # i ( strncmp str prefix n )
    ^ ? == c 0 1 0
}

@ nurl_str_find s haystack s needle → i {
    : s p # s ( strstr haystack needle )
    ? == # i p 0 { ^ -1 } {}
    ^ - # i p # i haystack
}

@ nurl_str_ends s str s suffix → i {
    : i slen ( strlen str )
    : i plen ( strlen suffix )
    ? > plen slen { ^ 0 } {}
    : i off - slen plen
    : *u sp # *u str
    : s base # s + # i sp off
    : i c # i ( memcmp base suffix plen )
    ^ ? == c 0 1 0
}

@ nurl_memmem_range s hay i hlen s needle i nlen → i {
    ? | < hlen 0 < nlen 0 { ^ -1 } {}
    ? == nlen 0 { ^ 0 } {}
    ? > nlen hlen { ^ -1 } {}
    : s p # s ( memmem hay hlen needle nlen )
    ? == # i p 0 { ^ -1 } {}
    ^ - # i p # i hay
}

// ── Batch C (2026-05-23): allocation-style ops via libc malloc + memcpy ──

@ nurl_str_get s str i idx → i {
    : i n ( strlen str )
    ? | < idx 0 >= idx n { ^ 0 } {}
    : *u p # *u str
    : u b . p idx
    ^ & # i b 255
}

@ nurl_str_cat s a s b → s {
    : i la ( strlen a )
    : i lb ( strlen b )
    : s r # s ( malloc + + la lb 1 )
    ( memcpy r a la )
    : *u rp # *u r
    : *u dst # *u + # i rp la
    ( memcpy # s dst b + lb 1 )
    ^ r
}

@ nurl_str_cat3 s a s b s c → s {
    : i la ( strlen a )
    : i lb ( strlen b )
    : i lc ( strlen c )
    : s r # s ( malloc + + + la lb lc 1 )
    ( memcpy r a la )
    : *u rp # *u r
    : *u d2 # *u + # i rp la
    ( memcpy # s d2 b lb )
    : *u d3 # *u + # i rp + la lb
    ( memcpy # s d3 c + lc 1 )
    ^ r
}

@ nurl_str_cat4 s a s b s c s d → s {
    : i la ( strlen a )
    : i lb ( strlen b )
    : i lc ( strlen c )
    : i ld ( strlen d )
    : s r # s ( malloc + + + + la lb lc ld 1 )
    ( memcpy r a la )
    : *u rp # *u r
    : *u d2 # *u + # i rp la
    ( memcpy # s d2 b lb )
    : *u d3 # *u + # i rp + la lb
    ( memcpy # s d3 c lc )
    : *u d4 # *u + # i rp + + la lb lc
    ( memcpy # s d4 d + ld 1 )
    ^ r
}

@ nurl_str_slice s str i start i n → s {
    : i slen ( strlen str )
    : ~ i st start
    : ~ i k n
    ? < st 0 { = st 0 } {}
    ? > st slen { = st slen } {}
    ? < k 0 { = k 0 } {}
    ? > + st k slen { = k - slen st } {}
    : s r # s ( malloc + k 1 )
    : *u sp # *u str
    : *u sat # *u + # i sp st
    ( memcpy r # s sat k )
    : *u rp # *u r
    : u zero # u 0
    = . rp k zero
    ^ r
}

@ nurl_parse_int_range s p i len → i {
    ? == # i p 0 { ^ 0 } {}
    ? <= len 0 { ^ 0 } {}
    : *u q # *u p
    : ~ i i 0
    : ~ i sign 1
    : u first . q 0
    ? == & # i first 255 45 { = sign -1  = i 1 } {}
    ? == & # i first 255 43 { = i 1 } {}
    : ~ i acc 0
    ~ < i len {
        : u c . q i
        : i ci & # i c 255
        ? | < ci 48 > ci 57 { ^ * acc sign } {}
        = acc + * acc 10 - ci 48
        = i + i 1
    }
    ^ * acc sign
}

// ── Phase 7 (2026-05-23): nurl_file_exists via libc access(2).
// nurlc.nu uses it to probe stage-0 sentinel files; mirrored here
// because nurlc.nu can't `$`-import its own stdlib/std/fs.nu.

@ nurl_file_exists s path → i {
    ? == # i path 0 { ^ 0 } {}
    : i32 rc ( access path # i32 0 )    // F_OK = 0
    ^ ? == # i rc 0 1 0
}

// ── Batch D' (2026-05-23): strtod via FFI for byte-range float parse.
// nurl_str_int / _str_float keep their C bodies (see runtime.c for
// the rationale).

// Parse f64 from byte range [p, p+len). Copies into a NUL-terminated
// scratch buffer and hands it to libc `strtod` (NULL endptr — we
// don't surface the parse position). Returns 0.0 on empty / null
// input; mirrors strtod's "0.0 on parse failure" behaviour for any
// input strtod itself rejects.
@ nurl_parse_float_range s p i len → f {
    ? == # i p 0 { ^ 0.0 } {}
    ? <= len 0 { ^ 0.0 } {}
    : s buf # s ( malloc + len 1 )
    ( memcpy buf p len )
    : *u bp # *u buf
    : u zero # u 0
    = . bp len zero
    : **u endptr # **u 0
    : f v ( strtod buf endptr )
    ( free buf )
    ^ v
}

@ __is_operator_callee i tt → b {
    ? == tt TT_DOT { ^ T } {}
    ? == tt TT_HASH { ^ T } {}
    ? == tt TT_CARET { ^ T } {}
    ? == tt TT_CARETCARET { ^ T } {}
    ? == tt TT_PLUS { ^ T } {}
    ? == tt TT_MINUS { ^ T } {}
    ? == tt TT_STAR { ^ T } {}
    ? == tt TT_SLASH { ^ T } {}
    ? == tt TT_PERCENT { ^ T } {}
    ? == tt TT_AMP { ^ T } {}
    ? == tt TT_PIPE { ^ T } {}
    ? == tt TT_LT { ^ T } {}
    ? == tt TT_GT { ^ T } {}
    ? == tt TT_EQEQ { ^ T } {}
    ? == tt TT_NE { ^ T } {}
    ? == tt TT_LE { ^ T } {}
    ? == tt TT_GE { ^ T } {}
    ? == tt TT_SHL { ^ T } {}
    ? == tt TT_SHR { ^ T } {}
    ^ F
}

@ gen_call i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s fname ( nurl_lex_val lex )
    ? ( __is_operator_callee ( nurl_lex_type lex ) )
    { ( die lex ( nurl_str_cat3
        `operator '` fname
        `' cannot be a call target: '(' begins a function call, but operator expressions are written without parentheses (e.g. '. obj field', not '( . obj field )')` ) ) }
    {}
    ( nurl_lex_advance lex )
    // Tail-call optimisation: snapshot + consume the tail-position
    // flag at function entry. Argument evaluation below recurses
    // through gen_expr → gen_call; clearing the flag here means
    // those nested calls don't get treated as tail (they aren't —
    // we're still building the outermost call's argument list).
    : b is_tail_position ( seq ( nurl_sym_get syms `__tail_call_pending__` ) `1` )
    ( nurl_sym_def syms `__tail_call_pending__` `` )
    // Visibility check (grammar v2.0). If the base fname is an @-defined
    // function registered by scan_fn_sigs, we know its source-file of
    // origin. A cross-file call is rejected when the callee's file is in
    // strict-mode AND the callee was not marked `pub`. Symbols without a
    // __src_file entry (FFI, trait/impl methods, runtime helpers, generic
    // mangled call_names) skip the check.
    : s callee_sf ( nurl_sym_get g_vis_syms ( nurl_str_cat fname `__src_file` ) )
    : s here_sf ( vis_current_src_file )
    ? & != 0 ( nurl_str_len callee_sf ) ! ( seq callee_sf here_sf )
    { : s strict ( nurl_sym_get g_vis_syms ( nurl_str_cat callee_sf `__strict` ) )
        : s is_pub ( nurl_sym_get g_vis_syms ( nurl_str_cat fname `__pub` ) )
        ? & ( seq strict `1` ) ! ( seq is_pub `1` )
        { ( die lex ( nurl_str_cat4
            `private function '` fname `' is not visible across files; defined in '` callee_sf ) ) }
        {}
    }
    {}
    // Generic instantiation: ( fname [T1 T2...] args... )
    : s call_name fname
    ? == ( nurl_lex_type lex ) TT_LBRACK
    { ( nurl_lex_advance lex )  // consume '['
        : s type_args ``
        : s mangle_sfx ``
        ~ != ( nurl_lex_type lex ) TT_RBRACK {
            : i tt_arg ( nurl_lex_type lex )
            : s ta ``
            // Compound named-struct type arg `( Name X Y ... )` is parsed
            // via parse_type → returns "%Name__X__Y...". Strip the leading
            // '%' so the result is a single ident-shaped word that
            // (a) substitutes safely into the generic body's source, and
            // (b) re-parses as the same named type wherever it appears.
            // Anonymous compound types (closures, slice/opt/res literals)
            // are not yet supported as generic call type-args.
            ? == tt_arg TT_LPAREN
            { : s lt ( parse_type lex )
                : i ll ( nurl_str_len lt )
                ? & > ll 0 == ( nurl_str_get lt 0 ) 37
                { = ta ( nurl_str_slice lt 1 - ll 1 ) }
                { = ta lt }
            }
            { = ta ( nurl_lex_val lex )
                ( nurl_lex_advance lex )
            }
            = type_args ? == 0 ( nurl_str_len type_args ) ta
            ( nurl_str_cat type_args ( nurl_str_cat ` ` ta ) )
            = mangle_sfx ( nurl_str_cat mangle_sfx ( nurl_str_cat `__` ( mangle_type ( llvm_type ta ) ) ) )
        }
        ( expect lex TT_RBRACK )
        : s mangled ( nurl_str_cat fname mangle_sfx )
        // Dedup uses a global key (g_generic_syms is scope-free) because
        // local `syms` is push/popped per block — registering ret_ty in
        // syms inside a loop body would vanish when that block ends, and
        // the next call site outside the loop would defer again.
        : s gkey ( nurl_str_cat `__inst_` mangled )
        : s g_already ( nurl_sym_get g_generic_syms gkey )
        ? == 0 ( nurl_str_len g_already )
        { ( defer_instantiation fname mangled type_args syms )
            ( nurl_sym_def g_generic_syms gkey `1` ) }
        { : s already ( nurl_sym_get syms mangled )
            ? == 0 ( nurl_str_len already )
            { : s rt ( compute_generic_ret_ty fname type_args )
                ( nurl_sym_def syms mangled rt ) }
            {} }
        = call_name mangled
    }
    {}
    : s argstr ``
    : i first 1
    : s first_arg_type ``
    // Variadic FFI (grammar v1.9): if gen_ffi_decl tagged this function
    // with `<fname>__variadic`, apply C default argument promotions to
    // every arg whose 0-based index is >= the fixed-param count. FFI
    // decls are never generic, so the variadic flag is keyed on fname
    // rather than the mangled call_name.
    : b is_variadic ( seq ( nurl_sym_get syms ( nurl_str_cat fname `__variadic` ) ) `1` )
    : s vf_str ( nurl_sym_get syms ( nurl_str_cat fname `__variadic_fixed` ) )
    : i fixed_count ? == 0 ( nurl_str_len vf_str ) 0 ( nurl_str_to_int vf_str )
    // Closure-escape gate (docs/GOTCHAS.md item 8 / BORROW.md Phase 3).
    // These four callees take an argument that outlives the current
    // scope — pushing into a heap-backed container or detaching onto a
    // worker thread. A value that is a *stack reference* (a closure
    // capturing a binding by pointer, or an aggregate / binding
    // holding one — see the escape-analysis section near
    // borrowck_fn_end) MUST NOT escape through any of these without
    // first being moved to a heap-backed handle, or the captured
    // stack slot dangles the moment its owning function returns. The
    // check is --borrowck-gated and warns (not dies) — BORROW.md
    // watch #3: a new rule ships as a warning until proven
    // false-positive-free across the whole corpus.
    : b is_escape_call | | |
        ( seq fname `vec_push` )
        ( seq fname `vec_insert` )
        ( seq fname `vec_set` )
        ( seq fname `thread_spawn` )
    // Phase 1 borrow: a `*_free` destructor consumes (frees) its first
    // argument. `nurl_free` is excluded — it frees raw *T / i8* FFI
    // memory, which BORROW.md item 5 leaves unchecked.
    : b is_consume_call & ( bck_is_destructor_name fname )
        ! ( seq fname `nurl_free` )
    : i arg_idx 0
    // BORROW.md Phase 4: space-separated 0-based indices of the
    // callee's `inout` parameters (recorded into g_fn_inout by
    // gen_fn_decl_concrete as the callee is compiled). An argument at
    // one of these positions is passed by address — see the
    // per-argument handling below. Empty for an ordinary function.
    : ~ s callee_inout ( nurl_sym_get g_fn_inout call_name )
    // BORROW.md Phase 4: indices of the callee's `sink` parameters —
    // an argument there is consumed (move-checked at the call site).
    : ~ s callee_sink ( nurl_sym_get g_fn_sink call_name )
    // Generic call: g_fn_inout / g_fn_sink for a generic function are
    // keyed by the GENERIC name (the index sets are type-independent,
    // computed once by compute_generic_inout_sink). The mangled
    // call_name gets its own entry only once the deferred
    // instantiation is compiled — too late for this call site. When
    // call_name is a mangled generic name (call_name != fname) with no
    // direct entry, fall back to the generic-name lookup.
    ? & == 0 ( nurl_str_len callee_inout ) ! ( seq call_name fname )
    { = callee_inout ( nurl_sym_get g_fn_inout fname ) }
    {}
    ? & == 0 ( nurl_str_len callee_sink ) ! ( seq call_name fname )
    { = callee_sink ( nurl_sym_get g_fn_sink fname ) }
    {}
    // If the callee is known (scan_fn_sigs) to have `inout` parameters
    // but g_fn_inout still has no entry, it is being called BEFORE its
    // definition was compiled — passing the argument by value would
    // mismatch the `<T>*` parameter and miscompile silently. Holds for
    // both ordinary and generic functions: scan_fn_sigs records
    // `<fname>__has_inout` for either. Reject it.
    ? & == 0 ( nurl_str_len callee_inout )
          ( seq ( nurl_sym_get syms ( nurl_str_cat fname `__has_inout` ) ) `1` )
    { ( die lex ( nurl_str_cat3
        `function '` fname
        `' has 'inout' parameters and must be defined before it is called - move its definition above this call site` ) ) }
    {}
    // Phase 2B parameter-ownership: collect register values for arg expressions
    // whose result is a fresh owned-string allocation (e.g. `nurl_str_cat`),
    // then free them right after the call returns. Without this the temp is
    // never released and leaks for the rest of the function's lifetime.
    // Convention: callees borrow i8* args and must `strdup` if they retain
    // (see runtime.c hardening for nurl_set_last_type, nurl_sym_get, ...).
    : s owned_arg_temps ``
    // BORROW.md Phase 5 (N-readers-XOR-1-writer): a binding passed to
    // this call as `inout` is mutably borrowed for the call's
    // duration; it must be the *exclusive* path to that value at the
    // call. `p5_seen` accumulates every bare-identifier argument and
    // `p5_inout_seen` the `inout` ones, so a binding that is both
    // mutably borrowed and aliased by another argument is flagged.
    : ~ s p5_seen ``
    : ~ s p5_inout_seen ``
    ~ != ( nurl_lex_type lex ) TT_RPAREN {
        // Phase 1 borrow: snapshot this argument's first token. A move
        // is recorded only when the consumed argument is a bare
        // identifier (first token IDENT/TYPE_KW) — `. h name` and other
        // compound expressions merely load an ident, they do not move
        // the binding the loaded ident names.
        : i bck_arg_tt ( nurl_lex_type lex )
        : s bck_arg_val ( nurl_lex_val lex )
        : i bck_arg_line ( nurl_lex_line lex )
        ( nurl_sym_def syms `__last_call_ret_owned__` `` )
        ( nurl_sym_def syms `__last_unsigned__` `` )
        // Reset __last_ident_name__ so the post-gen_expr check below
        // sees an ident only when this argument actually loaded one.
        ( nurl_sym_def syms `__last_ident_name__` `` )
        // Reset the escape side-channel so the escape check observes
        // only what THIS argument expression publishes.
        ( nurl_sym_def syms `__last_expr_refdepth__` `` )
        // BORROW.md Phase 4: an argument at an `inout` parameter
        // position is passed BY ADDRESS, not by value. It must be a
        // bare mutable (`: ~`) binding — the callee mutates it in
        // place. Pass the binding's backing pointer (`__ptr`) typed
        // `<T>*`; emit no value load. Everything else is the ordinary
        // by-value path.
        : b is_inout_arg ( str_contains_word callee_inout ( nurl_str_int arg_idx ) )
        // BORROW.md Phase 5: exclusive-access check. A bare-identifier
        // argument that is mutably borrowed (`inout`) here must not be
        // aliased by another bare-identifier argument of the SAME call
        // (whether that other one is `inout` or a plain by-value read)
        // — N readers XOR 1 writer. Reading a binding through a nested
        // sub-expression argument is a known gap (a later phase).
        ? & != g_borrowck 0 ( is_ident_tok bck_arg_tt )
        { ? | & is_inout_arg ( str_contains_word p5_seen bck_arg_val )
              & ! is_inout_arg ( str_contains_word p5_inout_seen bck_arg_val )
            { ( bck_esc_warn lex bck_arg_line ( nurl_str_cat3
                `'` bck_arg_val
                `' is both mutably borrowed (passed as 'inout') and aliased by another argument of the same call - exclusive access is violated` ) ) }
            {}
            = p5_seen ? == 0 ( nurl_str_len p5_seen )
                bck_arg_val ( nurl_str_cat3 p5_seen ` ` bck_arg_val )
            ? is_inout_arg
            { = p5_inout_seen ? == 0 ( nurl_str_len p5_inout_seen )
                bck_arg_val ( nurl_str_cat3 p5_inout_seen ` ` bck_arg_val ) }
            {}
            // BORROW.md Phase 6: iterator invalidation. If this
            // bare-identifier argument names a container currently
            // being iterated by an enclosing `~` foreach, and the
            // call mutates it — the receiver (arg 0) of a stdlib
            // container mutator, or any `inout` argument — the loop's
            // borrowed cursor would be invalidated.
            : b fe_iterated ( str_contains_word
                ( nurl_sym_get g_bck `iter_containers` ) bck_arg_val )
            : b fe_mutates & == arg_idx 0 ( bck_is_container_mutator fname )
            ? & fe_iterated | is_inout_arg fe_mutates
            { ( bck_esc_warn lex bck_arg_line ( nurl_str_cat3
                `cannot mutate '` bck_arg_val
                `' while iterating over it - the '~' loop holds a borrow of the container; move the mutation out of the loop body` ) ) }
            {} }
        {}
        : ~ s av ``
        : ~ s at ``
        ? is_inout_arg
        { ? == bck_arg_tt TT_DOT
            { // BORROW.md Phase 4: `inout` field target — `. obj field`.
              // Pass the field's address so the callee mutates exactly
              // that field of the caller's struct in place.
                = av ( gen_inout_field_addr lex syms cg fname )
                = at ( nurl_get_last_type )
            }
            { ? ! ( is_ident_tok bck_arg_tt )
                { ( die lex ( nurl_str_cat3 `inout argument to '` fname `' must be a mutable ': ~' binding or a '. binding field' field target, not an expression` ) ) }
                {}
                : s iptr ( nurl_sym_get syms ( nurl_str_cat bck_arg_val `__ptr` ) )
                : s ity ( nurl_sym_get syms bck_arg_val )
                ? == 0 ( nurl_str_len iptr )
                { ( die lex ( nurl_str_cat3 `inout argument '` bck_arg_val `' is not a binding in scope` ) ) }
                {}
                ? == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat bck_arg_val `__mutable` ) ) )
                { ( die lex ( nurl_str_cat3 `inout argument '` bck_arg_val `' must be a mutable ': ~' binding - the callee mutates it in place` ) ) }
                {}
                ( nurl_lex_advance lex )
                = av iptr
                = at ( nurl_str_cat ity `*` )
            }
        }
        { = av ( gen_expr lex syms cg )
            = at ( nurl_get_last_type )
        }
        : s lu_arg ( nurl_sym_get syms `__last_unsigned__` )
        // GOTCHAS.md item 2: `nurl_str_len` vs `string_len` confusion.
        // `nurl_str_len` is the FFI to libc strlen and expects `s`
        // (i8*); passing a `%String` struct reads the struct bytes as
        // a pointer and returns garbage (bit us in manifest_parse).
        // `string_len` is the stdlib wrapper and expects a `%String`;
        // passing a raw i8* misreads the C-string pointer as a struct
        // handle. Both shapes are pure type mismatches detectable at
        // call time. Die — the result is silent UB otherwise.
        ? & == arg_idx 0 ( seq fname `nurl_str_len` )
        { ? ( seq at `%String` )
            { ( die lex `nurl_str_len expects 's' (i8* C-string), got %String. Use 'string_len' for String values. See docs/GOTCHAS.md item 7.` ) }
            {} }
        {}
        ? & == arg_idx 0 ( seq fname `string_len` )
        { ? ( seq at `i8*` )
            { ( die lex `string_len expects %String, got 'i8*' (raw C-string). Use 'nurl_str_len' for raw C-string pointers. See docs/GOTCHAS.md item 7.` ) }
            {} }
        {}
        // Escape analysis (BORROW.md Phase 3, closes docs/GOTCHAS.md
        // item 8). If this call is one of the four ownership-taking
        // helpers AND this argument is a stack reference — a closure
        // literal capturing a binding by pointer, or a binding /
        // aggregate holding one — warn: the captured stack slot will
        // dangle the moment the surrounding function returns.
        ? is_escape_call
        { ( bck_esc_check_call_arg lex syms bck_arg_line
            ( nurl_sym_get syms `__last_ident_name__` ) fname ) }
        {}
        // Phase 1 borrow: a `*_free` destructor's first argument, when
        // it is a bare identifier, names a binding being consumed —
        // stash it as a move (flushed after the enclosing statement).
        ? & & is_consume_call == arg_idx 0 ( is_ident_tok bck_arg_tt )
        { ( bck_stash_move bck_arg_val ( nurl_lex_line lex ) ) }
        {}
        // BORROW.md Phase 4: a `sink` parameter consumes its argument.
        // When the argument is a bare-identifier binding, record it as
        // moved so any later use is a use-after-move. A binding that
        // the compiler auto-drops (owned slice / string / Drop value /
        // struct with owned fields) cannot yet be `sink`-passed — that
        // needs drop-ownership transfer to the callee (deferred); it
        // is rejected here rather than risking a double free.
        ? & ( str_contains_word callee_sink ( nurl_str_int arg_idx ) )
             ( is_ident_tok bck_arg_tt )
        { : s sink_ptr ( nurl_sym_get syms ( nurl_str_cat bck_arg_val `__ptr` ) )
            ? | | ( str_contains_word ( nurl_sym_get syms `__owned_slices__` ) bck_arg_val )
                  ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) sink_ptr )
                | ( str_contains_word ( nurl_sym_get syms `__user_drops__` ) sink_ptr )
                  ( str_contains_word ( nurl_sym_get syms `__owned_struct_fields__` ) sink_ptr )
            { ( die lex ( nurl_str_cat3
                `'` bck_arg_val
                `' is a compiler-auto-dropped value; passing it to a 'sink' parameter is not yet supported (BORROW.md Phase 4) - pass a Vec or other manually-managed handle, or pass it as an ordinary parameter` ) ) }
            { ( bck_stash_move bck_arg_val ( nurl_lex_line lex ) ) } }
        {}
        // Variadic position: promote BEFORE owned-temp tracking + argstr
        // append, since promotion replaces (at, av) with the widened pair.
        // i8*/i64/i32/double/pointers pass through variadic_promote_arg
        // unchanged.
        ? & is_variadic >= arg_idx fixed_count
        { = av ( variadic_promote_arg cg at av lu_arg )
            = at ( variadic_promoted_type at )
        }
        {}
        ? & & != 0 g_auto_drop_strings
        ( seq at `i8*` )
        ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` )
        { = owned_arg_temps ? == 0 ( nurl_str_len owned_arg_temps )
            av
            ( nurl_str_cat3 owned_arg_temps ` ` av ) }
        {}
        ? != first 0
        { = argstr ( nurl_str_cat3 at ` ` av )
            = first 0
            = first_arg_type at
        }
        { = argstr ( nurl_str_cat argstr ( nurl_str_cat4 `, ` at ` ` av ) ) }
        = arg_idx + arg_idx 1
    }
    // Call-arity check. scan_fn_sigs records every non-generic
    // @-function's declared parameter count as `<fname>__arity`. A call
    // with the wrong argument count otherwise emits a malformed `call`
    // the LLVM verifier rejects far from the source — or, with too few
    // arguments, silently miscompiles. The check runs while the lexer
    // still sits on the closing `)`, so the diagnostic points at the
    // call itself. Skipped for generic calls (call_name != fname), for
    // variadic FFI, and for a callee shadowed by a local binding
    // (closure / fn-pointer — `<fname>__ptr` is set); none of those
    // carry an `__arity` entry anyway, the `__ptr` guard just makes the
    // skip explicit against a same-named local.
    // `ar_s` is `?` when scan_fn_sigs saw conflicting definitions of
    // the name (different parameter counts) — skip the check then.
    : s ar_s ( nurl_sym_get syms ( nurl_str_cat fname `__arity` ) )
    ? & & & & ( seq call_name fname ) ! is_variadic
          != 0 ( nurl_str_len ar_s ) ! ( seq ar_s `?` )
          == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__ptr` ) ) )
    { : i ar_want ( nurl_str_to_int ar_s )
        ? != ar_want arg_idx
        { ( die lex ( nurl_str_cat3
            ( nurl_str_cat3 `call to '` fname `' has the wrong number of arguments: expected ` )
            ( nurl_str_cat3 ( nurl_str_int ar_want ) `, got ` ( nurl_str_int arg_idx ) )
            ` — every NURL operator has fixed arity, so a missing or extra argument shifts every token after it; check this call.` ) ) }
        {} }
    {}
    ( expect lex TT_RPAREN )
    // Escape analysis: a call's RESULT is never a stack reference —
    // returning a borrow into a parameter is interprocedural (BORROW.md
    // Phase 7, not yet implemented). Clear the side-channel an argument
    // closure / aggregate literal may have left set, so the enclosing
    // gen_let / gen_ret does not mis-read `( f \ → v {…} )` as one.
    ( nurl_sym_def syms `__last_expr_refdepth__` `` )
    // Group F: impl method dispatch based on first arg's LLVM type
    : s impl_key ( nurl_str_cat fname ( nurl_str_cat `##` first_arg_type ) )
    : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
    ? != 0 ( nurl_str_len impl_mangle_key )
    { : s impl_ret ( nurl_sym_get g_impl_ret_syms impl_key )
        : s impl_name ( nurl_str_cat fname ( nurl_str_cat `__` impl_mangle_key ) )
        ? ( seq impl_ret `void` )
        { ( nurl_print `  call void @` ) ( nurl_print impl_name )
            ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
            ( mem_drop_arg_temps owned_arg_temps )
            ( nurl_set_last_type `void` )
            ^ `undef`
        }
        { : s res ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = call ` ) ( nurl_print impl_ret )
            ( nurl_print ` @` ) ( nurl_print impl_name )
            ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
            ( mem_drop_arg_temps owned_arg_temps )
            ( nurl_set_last_type impl_ret )
            ^ res
        }
    }
    {}
    // Regular call
    : s rl ( nurl_sym_get syms call_name )
    : s rlt ? == 0 ( nurl_str_len rl ) `i64` rl
    // Track NURL return type for try-propagation type checking
    ( nurl_sym_def syms `__last_nurl_call__` ( nurl_sym_get syms ( nurl_str_cat call_name `__nurl_ret` ) ) )
    // Propagate slice-ownership from callee to caller's let-binding.
    // Values: "1" = owned slice (Phase 2A), "str" = owned string (Phase 2B).
    // When Phase 2B is off no function ever gets "str" registered, so behaviour
    // is identical to the Phase 2A-only build.
    ( nurl_sym_def syms `__last_call_ret_owned__` ( nurl_sym_get syms ( nurl_str_cat call_name `__ret_owned` ) ) )

    // Check if this is a stored closure variable first
    : s var_ptr ( nurl_sym_get syms ( nurl_str_cat call_name `__ptr` ) )
    : s call_type ( nurl_sym_get syms call_name )
    : b has_var_ptr != 0 ( nurl_str_len var_ptr )
    : b is_fn_type | | | | != 0 ( nurl_str_starts call_type `i64 (` ) != 0 ( nurl_str_starts call_type `void (` ) != 0 ( nurl_str_starts call_type `i8* (` ) != 0 ( nurl_str_starts call_type `i8*(` ) != 0 ( nurl_str_starts call_type `{` )
    : b is_stored_closure & has_var_ptr is_fn_type

    // Check if this is a function pointer parameter
    : s param_marker ( nurl_sym_get syms ( nurl_str_cat call_name `__param` ) )
    : b is_function_pointer != 0 ( nurl_str_len param_marker )
    : s var_llvm_val ? is_function_pointer ( nurl_str_cat `%` call_name ) ``

    ? is_stored_closure
    {
        // This is a stored closure variable - load and call
        : s loaded_closure ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print loaded_closure )
        ( nurl_print ` = load ` ) ( nurl_print call_type )
        ( nurl_print `, ` ) ( nurl_print call_type ) ( nurl_print `* ` )
        ( nurl_print var_ptr ) ( nurl_print `\n` )

        : s final_result ``
        ? ( str_contains call_type `{` )
        {
            // Closure struct - extract function pointer and call with environment
            = final_result ( call_closure_function loaded_closure call_type argstr cg )
        }
        {
            // Simple function pointer - call directly
            : s fn_ret_type ( extract_fn_ptr_return_type rlt )
            : s res ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = call ` ) ( nurl_print fn_ret_type )
            ( nurl_print ` ` ) ( nurl_print loaded_closure )
            ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
            ( nurl_set_last_type fn_ret_type )
            = final_result res
        }
        ( mem_drop_arg_temps owned_arg_temps )
        final_result
    }
    { ? is_function_pointer
        {
            // This is a function pointer parameter
            : s final_result ``
            ? ( str_contains call_type `{` )
            {  // Closure struct parameter
                = final_result ( call_closure_function var_llvm_val call_type argstr cg )
            }
            {  // Simple function pointer parameter - call directly
                : s fn_return_type ( extract_fn_ptr_return_type rlt )
                : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = call ` ) ( nurl_print fn_return_type )
                ( nurl_print ` ` ) ( nurl_print var_llvm_val )
                ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
                ( nurl_set_last_type fn_return_type )
                = final_result res
            }
            ( mem_drop_arg_temps owned_arg_temps )
            final_result
        }
        {
            // Regular function call
            // Tail-call optimisation: prepend `tail ` to the call
            // instruction when we're in tail position AND the callee's
            // return type matches the caller's. LLVM's `tail` marker
            // is a hint — the optimiser will silently drop it if it
            // can't safely turn the call into a jump (e.g. caller
            // alloca-pointer escapes through an arg), so this is
            // optimisation-only; correctness can't regress. `musttail`
            // would force the rewrite but adds stricter requirements
            // (identical signatures, no varargs, no caller-allocas in
            // args) — too brittle for NURL's owning ABI. Variadic FFI
            // is excluded since the C default-arg promotions would
            // make the callee signature differ from the caller's
            // declared one. Cross-file callees with unknown returns
            // (rlt == "i64" fallback at line above) still benefit
            // when the caller's return type also happens to be i64.
            : s fn_rt ( nurl_sym_get syms `__fn_ret_ty__` )
            : b tail_ok & & & is_tail_position
                ! ( seq rlt `void` )
                ! is_variadic
                ( seq rlt fn_rt )
            : s tail_kw ? tail_ok `tail ` ``
            ? ( seq rlt `void` )
            { ( nurl_print `  call void @` ) ( nurl_print call_name )
                ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
                ( mem_drop_arg_temps owned_arg_temps )
                ( nurl_set_last_type `void` )
                `undef`
            }
            { : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = ` ) ( nurl_print tail_kw )
                ( nurl_print `call ` ) ( nurl_print rlt )
                ( nurl_print ` @` ) ( nurl_print call_name )
                ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
                ( mem_drop_arg_temps owned_arg_temps )
                ( nurl_set_last_type rlt )
                res
            }
        }
    }
}

// ── Conditional ? cond then else ──────────────────────────────────

@ gen_cond i lex i syms i cg → s {
    // Borrow checker (Phase 0d): source line of the `?`, for the
    // `cond`/`endcond` structural markers bracketing this conditional.
    : i bck_cline ( nurl_lex_line lex )
    ( nurl_lex_advance lex )
    : s cv ( gen_expr lex syms cg )
    : s ct ( nurl_get_last_type )
    // Allow non-i1 integer conditions (e.g. `? & i64a i64b { … }`) by
    // narrowing to i1 via `icmp ne … 0`.
    = cv ( coerce_to_i1 cv ct cg )
    : s lt ( nurl_cg_lbl cg `then` )
    : s le ( nurl_cg_lbl cg `else` )
    : s lend ( nurl_cg_lbl cg `end` )
    ( nurl_print `  br i1 ` ) ( nurl_print cv )
    ( nurl_print `, label %` ) ( nurl_print lt )
    ( nurl_print `, label %` ) ( nurl_print le ) ( emit_dbg_eol )
    ( emit ( nurl_str_cat lt `:` ) )
    // Push a symtab scope around each arm so that `:` bindings inside an arm
    // (notably their `__owned_strings__` entries) cannot leak into the sibling
    // arm's autodrop list. Without this, a return in the else-arm would emit
    // free() calls for allocas that are only populated on the then-arm path,
    // producing invalid IR that crashes LLVM's register allocator under -O2.
    : s old_strs_t ``
    : s old_structs_t ``
    : s old_user_t ``
    ? != 0 g_auto_drop_strings
    { = old_strs_t ( nurl_sym_get syms `__owned_strings__` )
        = old_structs_t ( nurl_sym_get syms `__owned_struct_fields__` )
        = old_user_t ( nurl_sym_get syms `__user_drops__` )
        ( nurl_sym_push syms )
    } {}
    ( nurl_sym_def syms `__cur_lbl__` lt )
    = g_did_ret 0
    // Borrow checker: open the conditional (Phase 0d) — the `cond` row
    // carries the just-parsed condition's reads — then arm the then-arm
    // `{` as a forward join (Phase 0c).
    ( bck_record `cond` `` bck_cline )
    ( bck_set_block_kind `cond-then` )
    : s tv ( gen_expr lex syms cg )
    : s tt2 ( nurl_get_last_type )
    : s tlbl ( nurl_sym_get syms `__cur_lbl__` )
    : i tdr g_did_ret
    ? == tdr 0
    {  // Phase 2D: arm-local fall-through drop. Only safe when the arm's
        // result type is void — otherwise tv may reference memory backed by
        // one of the arm-local allocas we're about to free (UAF in the phi
        // consumer at %lend). Arm-result ownership transfer would require
        // Phase 2A-style tracking; out of scope here.
        ? & != 0 g_auto_drop_strings ( seq tt2 `void` )
        { ( mem_drop_new_strings syms cg old_strs_t )
            ( mem_drop_new_struct_fields syms cg old_structs_t )
            ( mem_drop_new_user_drops syms cg old_user_t ) } {}
        ( nurl_print `  br label %` ) ( nurl_print lend ) ( emit_dbg_eol )
    } {}
    ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}
    ( emit ( nurl_str_cat le `:` ) )
    : s old_strs_e ``
    : s old_structs_e ``
    : s old_user_e ``
    ? != 0 g_auto_drop_strings
    { = old_strs_e ( nurl_sym_get syms `__owned_strings__` )
        = old_structs_e ( nurl_sym_get syms `__owned_struct_fields__` )
        = old_user_e ( nurl_sym_get syms `__user_drops__` )
        ( nurl_sym_push syms )
    } {}
    ( nurl_sym_def syms `__cur_lbl__` le )
    = g_did_ret 0
    // Borrow checker (Phase 0c): the else-arm `{` is a forward join.
    // Setting this also re-arms over any `cond-then` left pending by a
    // bare (block-less) then-arm.
    ( bck_set_block_kind `cond-else` )
    : s ev ( gen_expr lex syms cg )
    : s et2 ( nurl_get_last_type )
    : s elbl ( nurl_sym_get syms `__cur_lbl__` )
    : i edr g_did_ret
    ? == edr 0
    { ? & != 0 g_auto_drop_strings ( seq et2 `void` )
        { ( mem_drop_new_strings syms cg old_strs_e )
            ( mem_drop_new_struct_fields syms cg old_structs_e )
            ( mem_drop_new_user_drops syms cg old_user_e ) } {}
        ( nurl_print `  br label %` ) ( nurl_print lend ) ( emit_dbg_eol )
    } {}
    ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}
    // Borrow checker: disarm — a block-less else-arm would otherwise
    // leak `cond-else` onto the next sibling block (Phase 0c) — then
    // close the conditional with its `endcond` marker (Phase 0d).
    ( bck_set_block_kind `` )
    ( bck_record `endcond` `` bck_cline )
    ( emit ( nurl_str_cat lend `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lend )
    // The whole conditional only "did_ret" if BOTH branches did. If either
    // branch falls through, %lend is reachable and the parent must keep
    // emitting code (and a `br parent_end` from this position). Without
    // this reset, deeply chained `? a {} { ? b {} { ? c {} { ^ … } } }`
    // patterns leave g_did_ret=1 on the way out and the parent skips its
    // `br`, producing label cascades with no terminators (LLVM error
    // "expected instruction opcode").
    ? & != 0 tdr != 0 edr { ( emit_call_term `unreachable` ) = g_did_ret 1 } { = g_did_ret 0 }
    // GOTCHAS.md item 1 + grammar: `?` consumed bare expressions for
    // then/else, but the very next token is `{`. Almost always the
    // n-ary `&`/`|` foot-gun: user wrote `? & a b c d { then } { else }`
    // intending an n-ary AND, but `& a b` only takes 2 operands so
    // `c` and `d` got consumed as the bare then/else, and the
    // `{ ... }` blocks then run as side-effect statements. Warn —
    // the program compiles but the conditional logic is wrong.
    ? == ( nurl_lex_type lex ) TT_LBRACE
    { ( warn lex `'?' consumed bare then/else values, but a '{ ... }' block follows. Likely too few '&'/'|' operators in the condition (each is BINARY — write '& & a b c d' for n-ary). See docs/GOTCHAS.md item 1.` ) }
    {}
    // pick a consistent phi type: prefer the non-void live branch type;
    // if both live and types differ, fall back to void (no phi needed).
    : s phi_ty ? != 0 tdr et2 tt2
    : b types_ok | != 0 tdr | != 0 edr ( seq tt2 et2 )
    : s result `undef`
    ? == 0 g_did_ret
    { ? & ! ( seq phi_ty `void` ) types_ok
        { : s res ( nurl_cg_reg cg )
            ? & != 0 tdr == 0 edr
            { ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = phi ` ) ( nurl_print phi_ty )
                ( nurl_print ` [ ` ) ( nurl_print ev )
                ( nurl_print `, %` ) ( nurl_print elbl ) ( nurl_print ` ]\n` )
            }
            { ? & == 0 tdr != 0 edr
                { ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = phi ` ) ( nurl_print phi_ty )
                    ( nurl_print ` [ ` ) ( nurl_print tv )
                    ( nurl_print `, %` ) ( nurl_print tlbl ) ( nurl_print ` ]\n` )
                }
                { ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = phi ` ) ( nurl_print phi_ty )
                    ( nurl_print ` [ ` ) ( nurl_print tv )
                    ( nurl_print `, %` ) ( nurl_print tlbl )
                    ( nurl_print ` ], [ ` ) ( nurl_print ev )
                    ( nurl_print `, %` ) ( nurl_print elbl ) ( nurl_print ` ]\n` )
                }
            }
            ( nurl_set_last_type phi_ty )
            = result res
        }
        { ( nurl_set_last_type `void` ) }
    }
    {}
    result
}

// ── Pattern Match ?? expr { pattern → expr ... } ──────────────────

// emit_lit_check: emit IR that extracts payload at position `idx` from the
// matched enum value, compares it against integer literal `lit`, and falls
// through to the next check on success or branches to fail_label on mismatch.
// If `lit` is empty, emit nothing (that slot has no literal constraint).
@ emit_lit_check i cg i syms s match_val s match_type s pattern_name i idx s lit s fail_label → v {
    ? == 0 ( nurl_str_len lit ) {} {
        : s pt ( nurl_sym_get syms ( nurl_str_cat pattern_name
        ( nurl_str_cat `__payload__` ( nurl_str_int idx ) ) ) )
        : s raw_reg ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print raw_reg )
        ( nurl_print ` = extractvalue ` ) ( nurl_print match_type )
        ( nurl_print ` ` ) ( nurl_print match_val )
        ( nurl_print `, ` ) ( nurl_print ( nurl_str_int + idx 1 ) ) ( nurl_print `\n` )
        // Payload is stored as ptr — convert to i64 for the literal comparison.
        : s val_reg ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print val_reg )
        ( nurl_print ` = ptrtoint ptr ` ) ( nurl_print raw_reg ) ( nurl_print ` to i64\n` )
        : s cmp_reg ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print cmp_reg )
        ( nurl_print ` = icmp eq i64 ` ) ( nurl_print val_reg )
        ( nurl_print `, ` ) ( nurl_print lit ) ( nurl_print `\n` )
        : s ok_label ( nurl_cg_lbl cg `litok` )
        ( nurl_print `  br i1 ` ) ( nurl_print cmp_reg )
        ( nurl_print `, label %` ) ( nurl_print ok_label )
        ( nurl_print `, label %` ) ( nurl_print fail_label ) ( emit_dbg_eol )
        ( nurl_print ok_label ) ( nurl_print `:\n` )
    }
}

@ gen_match i lex i syms i cg → s {
    // Borrow checker (Phase 0d): source line of the `??`, for the
    // `match`/`endmatch` structural markers bracketing this match.
    : i bck_mline ( nurl_lex_line lex )
    ( nurl_lex_advance lex )  // consume '??'

    // Peek the variable name (if any) BEFORE gen_expr consumes it, so we
    // can later look up `<name>__res_nurl_T` (set by gen_let_or_struct)
    // to know the source-level NURL T of an `! T E` value being matched.
    : ~ s match_var_name ? ( is_ident_tok ( nurl_lex_type lex ) ) ( nurl_lex_val lex ) ``

    // Generate the value to match against. Clear __last_nurl_call__
    // first: for a non-binding scrutinee, a non-empty value afterwards
    // means the scrutinee's outermost operation was a call, and the
    // value is that callee's NURL return type (`! T E`).
    ( nurl_sym_def syms `__last_nurl_call__` `` )
    : s match_val ( gen_expr lex syms cg )
    : s match_type ( nurl_get_last_type )

    // A `?? ( f … )` whose scrutinee is a direct call has no binding
    // name, so the wide-payload reconstruction below (keyed on
    // `<name>__res_nurl_T` / `__res_t_llvm`) would be skipped — and a
    // wide `! T E` payload (a multi-field value struct) would be read
    // as its raw heap-box pointer (silent garbage). Synthesise a
    // binding name and populate those keys from the call's NURL return
    // type so the direct-call form reconstructs identically to `?? r`.
    ? & == 0 ( nurl_str_len match_var_name )
          != 0 ( nurl_str_len ( nurl_sym_get syms `__last_nurl_call__` ) )
    { : s mcall_nurl ( nurl_sym_get syms `__last_nurl_call__` )
        : s msynth ( nurl_str_cat `__matchtmp` ( nurl_cg_lbl cg `mt` ) )
        : s minner_t ( str_first_word ( str_skip_word mcall_nurl ) )
        : s minner_e ( str_first_word ( str_skip_word ( str_skip_word mcall_nurl ) ) )
        ( nurl_sym_def syms ( nurl_str_cat msynth `__res_nurl_T` ) minner_t )
        ( nurl_sym_def syms ( nurl_str_cat msynth `__res_nurl_E` ) minner_e )
        : s minner_llvm ( nurl_sym_get syms minner_t )
        ? != 0 ( nurl_str_len minner_llvm )
        { ( nurl_sym_def syms ( nurl_str_cat msynth `__res_t_llvm` ) minner_llvm ) }
        {}
        = match_var_name msynth }
    {}

    ( expect lex TT_LBRACE )  // expect '{'

    // Single merge label all live arms branch to.
    : s end_label ( nurl_cg_lbl cg `match_end` )

    // Phi-based result. Each non-returning arm contributes a
    //   (value, end-of-arm-block-label, type)
    // tuple; we emit a phi at end_label iff every live arm agrees on a
    // non-void type.  Otherwise the match has no value (statement context)
    // and last_type is set to void.
    //
    // This replaces an earlier alloca-typed-by-fn-return-type scheme that
    // emitted invalid IR whenever an arm body produced a value of a
    // different type than the enclosing function's return type — e.g. a
    // statement-position `?? prev { T c → { = count + c 1 } F → {} }`
    // inside a function returning HashMap stored an i64 into a HashMap*.
    : ~ s phi_entries ``
    : ~ s phi_type ``
    : ~ b phi_ok T
    : ~ i phi_count 0
    // arms_total / arms_ret count every parsed arm vs. those that ended
    // in `^`. When equal AND a fallback_pred is set, the `match_end`
    // label is reached only through the synthetic last-arm fallthrough
    // br — there is no real value flow, no phi entries, and the function
    // continues with no further code. Emit `unreachable` at end_label so
    // the function block is well-formed.
    : ~ i arms_total 0
    : ~ i arms_ret 0
    // fallback_pred = label of the open block right before the trailing
    // `br end_label` after the loop.  Empty when that br lands inside an
    // already-terminated block (wildcard-last) and is therefore dead.
    : ~ s fallback_pred ``

    // Exhaustive match tracking
    : s seen_variants ``
    : i has_wildcard 0

    // Borrow checker (Phase 0d): open the match — the `match` row
    // carries the scrutinee's reads. `endmatch` closes it after the
    // arm loop. The arms in between are `match-arm` blocks (braced
    // arms) interleaved with block-less bare arms; the bracket lets
    // the analyze walk scope them unambiguously.
    ( bck_record `match` `` bck_mline )

    // Process all match arms
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        : i pat_tt ( nurl_lex_type lex )
        ? | | ( is_ident_tok pat_tt ) == pat_tt TT_BOOL == pat_tt TT_INT {
            // Parse pattern. Three shapes:
            //   * IDENT / TYPE_KW — enum variant name (Some/None/Ok/Err/...).
            //   * BOOL — `T` / `F` for Option/Result Ok/Err arms.
            //   * INT — `?? n { 1 → ... 2 → ... _ → ... }` — direct equality
            //     check against the match value. Skips payload-binding,
            //     exhaustiveness tracking, and enum-variant lookup paths;
            //     a wildcard arm is required to cover the residual.
            : b is_int_pat == pat_tt TT_INT
            : s pattern_name ( nurl_lex_val lex )
            ( nurl_lex_advance lex )

            // Collect up to 3 payload slots before the arrow.  Each slot is either
            // an identifier (binds the payload) or an integer literal (compared).
            // Int-literal patterns carry no payload — skip the loop entirely.
            : s pv0 ``
            : s pv1 ``
            : s pv2 ``
            : s lit0 ``
            : s lit1 ``
            : s lit2 ``
            : i pvc 0
            ~ & ! is_int_pat != ( nurl_lex_type lex ) TT_ARROW {
                : i pst ( nurl_lex_type lex )
                ? ( is_ident_tok pst ) {
                    ? == pvc 0 { = pv0 ( nurl_lex_val lex ) } {}
                    ? == pvc 1 { = pv1 ( nurl_lex_val lex ) } {}
                    ? == pvc 2 { = pv2 ( nurl_lex_val lex ) } {}
                    = pvc + pvc 1
                    ( nurl_lex_advance lex )
                } {
                    ? == pst TT_INT {
                        : s ival ( nurl_lex_val lex )
                        ? == pvc 0 { = lit0 ival } {}
                        ? == pvc 1 { = lit1 ival } {}
                        ? == pvc 2 { = lit2 ival } {}
                        = pvc + pvc 1
                        ( nurl_lex_advance lex )
                    } {
                        ( die lex `expected arrow or payload variable` )
                    }
                }
            }
            : b has_lit | | != 0 ( nurl_str_len lit0 )
            != 0 ( nurl_str_len lit1 )
            != 0 ( nurl_str_len lit2 )

            ( expect lex TT_ARROW )  // expect '→'

            // Generate arm label; wildcard skips comparison and jumps directly
            : s arm_label ( nurl_cg_lbl cg `arm` )
            : s next_label ``
            ? ( seq pattern_name `_` ) {
                // Wildcard: unconditional branch — no tag load, no icmp
                = has_wildcard 1
                ( nurl_print `  br label %` ) ( nurl_print arm_label ) ( emit_dbg_eol )
            } { ? is_int_pat {
                // Integer-literal arm: direct equality compare against
                // the match value. No enum tag, no payload, no
                // exhaustiveness contribution. `match_type` must be an
                // integer LLVM type — we don't currently validate that,
                // a non-integer match would produce invalid IR LLVM
                // catches at link time.
                = next_label ( nurl_cg_lbl cg `next` )
                : s cmp_reg ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print cmp_reg )
                ( nurl_print ` = icmp eq ` ) ( nurl_print match_type )
                ( nurl_print ` ` ) ( nurl_print match_val )
                ( nurl_print `, ` ) ( nurl_print pattern_name ) ( nurl_print `\n` )
                ( nurl_print `  br i1 ` ) ( nurl_print cmp_reg )
                ( nurl_print `, label %` ) ( nurl_print arm_label )
                ( nurl_print `, label %` ) ( nurl_print next_label ) ( emit_dbg_eol )
            } {
                // Named variant.  Literal-constrained arms (e.g. `Ok 200`) do NOT
                // exhaustively cover the variant — only catch-all arms (no literals)
                // count towards exhaustiveness and as duplicate-arm blockers.
                ? ( str_contains_word seen_variants pattern_name ) {
                    ( die lex ( nurl_str_cat `duplicate match arm for variant: ` pattern_name ) )
                } {}
                ? has_lit {} {
                    = seen_variants ? == 0 ( nurl_str_len seen_variants )
                    pattern_name
                    ( nurl_str_cat seen_variants ( nurl_str_cat ` ` pattern_name ) )
                }
                // T/F: bool pattern matching i1 tag of Option — no global load needed
                : b is_bool_pat | ( seq pattern_name `T` ) ( seq pattern_name `F` )
                // If match_val is already a bare scalar tag (i1 from
                // `?? some_bool`; i64 from a nested `?? e` where `e` was
                // bound from an `F`-arm of `! T E` and is the enum's
                // raw i64 tag), use it directly — extractvalue is only
                // valid on aggregate types (`%Enum`, `{ i1, T }`,
                // `{ i64, ptr }` etc.). Without the i64 skip, the inner
                // emit `extractvalue i64 %tag, 0` triggered LLVM's
                // "extractvalue operand must be aggregate type". Closes
                // docs/GOTCHAS.md item 6 / memory gotcha #6.
                : b match_is_bare_tag | ( seq match_type `i1` ) ( seq match_type `i64` )
                : s tag_reg ? match_is_bare_tag match_val ( nurl_cg_reg cg )
                ? match_is_bare_tag {} {
                    ( nurl_print `  ` ) ( nurl_print tag_reg )
                    ( nurl_print ` = extractvalue ` ) ( nurl_print match_type )
                    ( nurl_print ` ` ) ( nurl_print match_val ) ( nurl_print `, 0\n` )
                }

                : s cmp_reg ( nurl_cg_reg cg )
                ? is_bool_pat
                { ( nurl_print `  ` ) ( nurl_print cmp_reg )
                    ( nurl_print ` = icmp eq i1 ` ) ( nurl_print tag_reg )
                    ( nurl_print `, ` )
                    ( nurl_print ? ( seq pattern_name `T` ) `1` `0` ) ( nurl_print `\n` )
                }
                { : s enum_const ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print enum_const )
                    ( nurl_print ` = load i64, i64* @` )
                    ( nurl_print pattern_name ) ( nurl_print `\n` )
                    ( nurl_print `  ` ) ( nurl_print cmp_reg )
                    ( nurl_print ` = icmp eq i64 ` ) ( nurl_print tag_reg )
                    ( nurl_print `, ` ) ( nurl_print enum_const ) ( nurl_print `\n` )
                }

                = next_label ( nurl_cg_lbl cg `next` )
                // If the pattern has literal constraints, jump to a literal-check
                // block first; otherwise branch straight to the arm body.
                : s tag_ok_label ? has_lit ( nurl_cg_lbl cg `litchk` ) arm_label
                ( nurl_print `  br i1 ` ) ( nurl_print cmp_reg )
                ( nurl_print `, label %` ) ( nurl_print tag_ok_label )
                ( nurl_print `, label %` ) ( nurl_print next_label ) ( emit_dbg_eol )
                // Emit chained literal comparisons.  Each failure jumps to next_label;
                // the last successful check falls through to arm_label.
                ? has_lit {
                    ( nurl_print tag_ok_label ) ( nurl_print `:\n` )
                    ( emit_lit_check cg syms match_val match_type pattern_name 0 lit0 next_label )
                    ( emit_lit_check cg syms match_val match_type pattern_name 1 lit1 next_label )
                    ( emit_lit_check cg syms match_val match_type pattern_name 2 lit2 next_label )
                    ( nurl_print `  br label %` ) ( nurl_print arm_label ) ( emit_dbg_eol )
                } {}
            } }

            // Generate the arm code
            ( nurl_print arm_label ) ( nurl_print `:\n` )
            ( nurl_sym_def syms `__cur_lbl__` arm_label )
            // Scope each match arm so payload bindings and owned-string entries
            // don't leak into sibling arms (see gen_cond for the same reasoning).
            : s old_strs_m ``
            : s old_structs_m ``
            ? != 0 g_auto_drop_strings
            { = old_strs_m ( nurl_sym_get syms `__owned_strings__` )
                = old_structs_m ( nurl_sym_get syms `__owned_struct_fields__` )
                ( nurl_sym_push syms )
            } {}

            // Bind first payload variable (enum field 1)
            ? != 0 ( nurl_str_len pv0 ) {
                : s pt0 ( nurl_sym_get syms ( nurl_str_cat pattern_name `__payload__0` ) )
                // Bool patterns (T/F) on opt/res have no symbol entry — the payload
                // type lives inside match_type as `{ i1, X }`. Strip the `{ i1, `
                // prefix and ` }` suffix to recover X. Unlike named-enum variants
                // whose payload is stored as opaque ptr, opt/res field 1 is already
                // stored at its real type, so no ptr→X conversion is required.
                : b pt0_is_opt_bool F
                ? & == 0 ( nurl_str_len pt0 )
                & | ( seq pattern_name `T` ) ( seq pattern_name `F` )
                & >= ( nurl_str_len match_type ) 6
                ( seq ( nurl_str_slice match_type 0 6 ) `{ i1, ` )
                { = pt0 ( nurl_str_slice match_type 6 - ( nurl_str_len match_type ) 8 )
                    = pt0_is_opt_bool T }
                {}
                : s pr0 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print pr0 )
                ( nurl_print ` = extractvalue ` ) ( nurl_print match_type )
                ( nurl_print ` ` ) ( nurl_print match_val ) ( nurl_print `, 1\n` )
                // Opt/res-bool fallback path: pt0 is the inner LLVM type of the
                // `{ i1, X }` aggregate (e.g. `i64` for `! Json ParseErr`). When
                // the source-level NURL T names a struct handle (Json, String, …)
                // — looked up via `<match_var>__res_nurl_T` set in gen_let_or_struct
                // — substitute pt0 with the struct's LLVM type so the alloca below
                // stores the reconstructed value at the right type. This lets the
                // user write `T j → ...` and have `j : %Json`.
                : ~ s pt0_eff pt0
                : ~ s pr0_eff pr0
                : ~ b did_reconstruct F
                ? & pt0_is_opt_bool != 0 ( nurl_str_len match_var_name )
                { : s nurl_key ( nurl_str_cat match_var_name
                    ? ( seq pattern_name `T` ) `__res_nurl_T` `__res_nurl_E` )
                    : s nurl_inner_t ( nurl_sym_get syms nurl_key )
                    // `f` (double) source type with i64 payload slot: bitcast back.
                    // Mirrors gen_agg_lit's double→i64 packing for `! f E` results.
                    ? & ( seq nurl_inner_t `f` ) ( seq pt0 `i64` )
                    { : s db_uc ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print db_uc )
                        ( nurl_print ` = bitcast i64 ` ) ( nurl_print pr0 )
                        ( nurl_print ` to double\n` )
                        = pt0_eff `double`
                        = pr0_eff db_uc
                        = did_reconstruct T
                    } {}
                    ? != 0 ( nurl_str_len nurl_inner_t )
                    { : ~ s nurl_inner_llvm ( nurl_sym_get syms nurl_inner_t )
                        // Fallback for paren-compound T (e.g. `( Vec u )`):
                        // `nurl_inner_t` was the literal `(` token from
                        // parse_type_res's `nurl_lex_val`-before-parse capture,
                        // which doesn't look up to anything. Use the saved
                        // LLVM type instead (T-arm only — F-arm reconstruction
                        // uses single-token enum names like NetErr/WsErr that
                        // round-trip through the NURL-source path fine).
                        ? & == 0 ( nurl_str_len nurl_inner_llvm ) ( seq pattern_name `T` )
                        { = nurl_inner_llvm ( nurl_sym_get syms ( nurl_str_cat match_var_name `__res_t_llvm` ) ) }
                        {}
                        ? & != 0 ( nurl_str_len nurl_inner_llvm )
                        == ( nurl_str_get nurl_inner_llvm 0 ) 37
                        { : s sname_r ( nurl_str_slice nurl_inner_llvm 1 - ( nurl_str_len nurl_inner_llvm ) 1 )
                            : s vlist_r ( nurl_sym_get syms ( nurl_str_cat sname_r `__variants` ) )
                            ? == 0 ( nurl_str_len vlist_r )
                            {  // Struct payload reconstruction. Two shapes:
                                //   (a) f0 is a pointer (Vec/String/Response):
                                //       i64 payload IS the struct's f0 pointer —
                                //       inttoptr + insertvalue at field 0.
                                //   (b) f0 is non-pointer (multi-field struct like
                                //       ParsedHead, HttpRequest, …): payload is a
                                //       heap-box pointer — inttoptr → %T* →
                                //       load → free.
                                : s ni_f0_ty ( nurl_sym_get syms ( nurl_str_cat3 sname_r `__idx_0` `__type` ) )
                                : b ni_f0_is_ptr & != 0 ( nurl_str_len ni_f0_ty )
                                == ( nurl_str_get ni_f0_ty - ( nurl_str_len ni_f0_ty ) 1 ) 42
                                ? ni_f0_is_ptr
                                { : s pcv_r ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print pcv_r )
                                    ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 )
                                    ( nurl_print ` to ` ) ( nurl_print ni_f0_ty ) ( nurl_print `\n` )
                                    : s sv_r ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print sv_r )
                                    ( nurl_print ` = insertvalue ` ) ( nurl_print nurl_inner_llvm )
                                    ( nurl_print ` undef, ` ) ( nurl_print ni_f0_ty )
                                    ( nurl_print ` ` ) ( nurl_print pcv_r ) ( nurl_print `, 0\n` )
                                    = pt0_eff nurl_inner_llvm
                                    = pr0_eff sv_r
                                    = did_reconstruct T }
                                ? != 0 ( nurl_str_len ni_f0_ty )
                                {  // Heap-box multi-field struct: load + free.
                                    : s ubp_s ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubp_s )
                                    ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 )
                                    ( nurl_print ` to ` ) ( nurl_print nurl_inner_llvm ) ( nurl_print `*\n` )
                                    : s ubv_s ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubv_s )
                                    ( nurl_print ` = load ` ) ( nurl_print nurl_inner_llvm )
                                    ( nurl_print `, ` ) ( nurl_print nurl_inner_llvm )
                                    ( nurl_print `* ` ) ( nurl_print ubp_s ) ( nurl_print `\n` )
                                    : s ubraw_s ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubraw_s )
                                    ( nurl_print ` = bitcast ` ) ( nurl_print nurl_inner_llvm )
                                    ( nurl_print `* ` ) ( nurl_print ubp_s ) ( nurl_print ` to i8*\n` )
                                    ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print ubraw_s ) ( nurl_print `)` ) ( emit_dbg_eol )
                                    = pt0_eff nurl_inner_llvm
                                    = pr0_eff ubv_s
                                    = did_reconstruct T }
                                {} }
                            {  // Wide enum unbox: i64 → %T*  → load %T → free.
                                // Narrow enums (no payloads) skip — they round-trip
                                // through gen_cast's i64→struct insertvalue path.
                                : s mp_r ( nurl_sym_get syms ( nurl_str_cat sname_r `__max_payloads` ) )
                                : i mp_rn ? != 0 ( nurl_str_len mp_r ) ( nurl_str_to_int mp_r ) 0
                                ? > mp_rn 0 {
                                    : s ubp ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubp )
                                    ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 )
                                    ( nurl_print ` to ` ) ( nurl_print nurl_inner_llvm ) ( nurl_print `*\n` )
                                    : s ubv ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubv )
                                    ( nurl_print ` = load ` ) ( nurl_print nurl_inner_llvm )
                                    ( nurl_print `, ` ) ( nurl_print nurl_inner_llvm )
                                    ( nurl_print `* ` ) ( nurl_print ubp ) ( nurl_print `\n` )
                                    : s ubraw ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubraw )
                                    ( nurl_print ` = bitcast ` ) ( nurl_print nurl_inner_llvm )
                                    ( nurl_print `* ` ) ( nurl_print ubp ) ( nurl_print ` to i8*\n` )
                                    ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print ubraw ) ( nurl_print `)` ) ( emit_dbg_eol )
                                    = pt0_eff nurl_inner_llvm
                                    = pr0_eff ubv
                                    = did_reconstruct T
                                } {} }
                        }
                        {} }
                    {} }
                {}
                : s cv0 ? did_reconstruct pr0_eff
                ? pt0_is_opt_bool pr0 ( nurl_cg_reg cg )
                ? pt0_is_opt_bool {} {
                    ? ( seq pt0 `i1` ) {
                        : s t64 ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print t64 )
                        ( nurl_print ` = ptrtoint ptr ` ) ( nurl_print pr0 ) ( nurl_print ` to i64\n` )
                        ( nurl_print `  ` ) ( nurl_print cv0 )
                        ( nurl_print ` = trunc i64 ` ) ( nurl_print t64 ) ( nurl_print ` to i1\n` )
                    } {
                        // Struct-handle payload (e.g. %Vec__Json, %String): the payload
                        // ptr stored in the enum slot IS the struct's field-0 pointer
                        // (because aggregate construction does the inverse — extractvalue
                        // 0 + ptrtoint into the i64 slot). Reconstruct by insertvalue.
                        : b pt0_is_struct_handle F
                        : s pt0_f0_ty ``
                        ? == ( nurl_str_get pt0 0 ) 37
                        { : s sname0 ( nurl_str_slice pt0 1 - ( nurl_str_len pt0 ) 1 )
                            : s var_list0 ( nurl_sym_get syms ( nurl_str_cat sname0 `__variants` ) )
                            ? == 0 ( nurl_str_len var_list0 )
                            { = pt0_f0_ty ( nurl_sym_get syms ( nurl_str_cat3 sname0 `__idx_0` `__type` ) )
                                ? & != 0 ( nurl_str_len pt0_f0_ty )
                                == ( nurl_str_get pt0_f0_ty - ( nurl_str_len pt0_f0_ty ) 1 ) 42
                                { = pt0_is_struct_handle T } {} }
                            {} }
                        {}
                        ? pt0_is_struct_handle
                        { ( nurl_print `  ` ) ( nurl_print cv0 )
                            ( nurl_print ` = insertvalue ` ) ( nurl_print pt0 )
                            ( nurl_print ` undef, ` ) ( nurl_print pt0_f0_ty )
                            ( nurl_print ` ` ) ( nurl_print pr0 ) ( nurl_print `, 0\n` ) }
                        { ( nurl_print `  ` ) ( nurl_print cv0 )
                            ? | == ( nurl_str_get pt0 0 ) 123
                                & == ( nurl_str_get pt0 0 ) 37
                                  != ( nurl_str_get pt0 - ( nurl_str_len pt0 ) 1 ) 42
                            {  // Anonymous aggregate (`{ i1, i64 }`) OR a named
                               // non-pointer type (`%Geom` multi-field struct /
                               // `%Color` enum) — the payload slot holds a
                               // heap-box pointer to the whole value (see the
                               // symmetric heap-box in gen_agg_lit's enum-
                               // construction path). Load the value back
                               // through it. A pointer payload (`%Ast*`) keeps
                               // the bitcast-fallthrough below — the slot holds
                               // the pointer itself, not a box.
                                ( nurl_print ` = load ` ) ( nurl_print pt0 )
                                ( nurl_print `, ptr ` ) ( nurl_print pr0 ) ( nurl_print `\n` )
                            }
                            ? ( seq pt0 `i64` )
                            { ( nurl_print ` = ptrtoint ptr ` ) ( nurl_print pr0 ) ( nurl_print ` to i64\n` ) }
                            { ( nurl_print ` = bitcast ptr ` ) ( nurl_print pr0 ) ( nurl_print ` to i8*\n` ) } }
                    }
                }
                : s vp0 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print vp0 )
                ( nurl_print ` = alloca ` ) ( nurl_print pt0_eff ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print pt0_eff )
                ( nurl_print ` ` ) ( nurl_print cv0 )
                ( nurl_print `, ` ) ( nurl_print pt0_eff )
                ( nurl_print `* ` ) ( nurl_print vp0 ) ( nurl_print `\n` )
                ( nurl_sym_def syms pv0 pt0_eff )
                ( nurl_sym_def syms ( nurl_str_cat pv0 `__ptr` ) vp0 )
                // Propagate unsigned flag for `?u` / `?u16` / `?u32` /
                // `?u64` matches. T-arm only (F-arm has no payload).
                // Without this, the alloca drops the unsigned-ness and a
                // downstream `# i b` cast in the arm body emits sext
                // instead of zext for high-bit-set bytes (bit us in
                // bytes_to_hex over SHA-1 digests printing the wrong
                // nibbles).
                ? & pt0_is_opt_bool & ( seq pattern_name `T` ) != 0 ( nurl_str_len match_var_name )
                { : s opt_t ( nurl_sym_get syms ( nurl_str_cat match_var_name `__opt_nurl_T` ) )
                    ? ( nurl_type_is_unsigned opt_t )
                    { ( nurl_sym_def syms ( nurl_str_cat pv0 `__unsigned` ) `1` ) }
                    {} }
                {}
            } {}
            // Bind second payload variable (enum field 2)
            ? != 0 ( nurl_str_len pv1 ) {
                : s pt1 ( nurl_sym_get syms ( nurl_str_cat pattern_name `__payload__1` ) )
                : s pr1 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print pr1 )
                ( nurl_print ` = extractvalue ` ) ( nurl_print match_type )
                ( nurl_print ` ` ) ( nurl_print match_val ) ( nurl_print `, 2\n` )
                : s cv1 ( nurl_cg_reg cg )
                ? ( seq pt1 `i1` ) {
                    : s t64 ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print t64 )
                    ( nurl_print ` = ptrtoint ptr ` ) ( nurl_print pr1 ) ( nurl_print ` to i64\n` )
                    ( nurl_print `  ` ) ( nurl_print cv1 )
                    ( nurl_print ` = trunc i64 ` ) ( nurl_print t64 ) ( nurl_print ` to i1\n` )
                } {
                    ( nurl_print `  ` ) ( nurl_print cv1 )
                    ? == ( nurl_str_get pt1 0 ) 123
                    {  // Anonymous aggregate: load value from ptr
                        ( nurl_print ` = load ` ) ( nurl_print pt1 )
                        ( nurl_print `, ptr ` ) ( nurl_print pr1 ) ( nurl_print `\n` )
                    }
                    ? ( seq pt1 `i64` )
                    { ( nurl_print ` = ptrtoint ptr ` ) ( nurl_print pr1 ) ( nurl_print ` to i64\n` ) }
                    { ( nurl_print ` = bitcast ptr ` ) ( nurl_print pr1 ) ( nurl_print ` to i8*\n` ) }
                }
                : s vp1 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print vp1 )
                ( nurl_print ` = alloca ` ) ( nurl_print pt1 ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print pt1 )
                ( nurl_print ` ` ) ( nurl_print cv1 )
                ( nurl_print `, ` ) ( nurl_print pt1 )
                ( nurl_print `* ` ) ( nurl_print vp1 ) ( nurl_print `\n` )
                ( nurl_sym_def syms pv1 pt1 )
                ( nurl_sym_def syms ( nurl_str_cat pv1 `__ptr` ) vp1 )
            } {}
            // Bind third payload variable (enum field 3)
            ? != 0 ( nurl_str_len pv2 ) {
                : s pt2 ( nurl_sym_get syms ( nurl_str_cat pattern_name `__payload__2` ) )
                : s pr2 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print pr2 )
                ( nurl_print ` = extractvalue ` ) ( nurl_print match_type )
                ( nurl_print ` ` ) ( nurl_print match_val ) ( nurl_print `, 3\n` )
                : s cv2 ( nurl_cg_reg cg )
                ? ( seq pt2 `i1` ) {
                    : s t64 ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print t64 )
                    ( nurl_print ` = ptrtoint ptr ` ) ( nurl_print pr2 ) ( nurl_print ` to i64\n` )
                    ( nurl_print `  ` ) ( nurl_print cv2 )
                    ( nurl_print ` = trunc i64 ` ) ( nurl_print t64 ) ( nurl_print ` to i1\n` )
                } {
                    ( nurl_print `  ` ) ( nurl_print cv2 )
                    ? == ( nurl_str_get pt2 0 ) 123
                    {  // Anonymous aggregate: load value from ptr
                        ( nurl_print ` = load ` ) ( nurl_print pt2 )
                        ( nurl_print `, ptr ` ) ( nurl_print pr2 ) ( nurl_print `\n` )
                    }
                    ? ( seq pt2 `i64` )
                    { ( nurl_print ` = ptrtoint ptr ` ) ( nurl_print pr2 ) ( nurl_print ` to i64\n` ) }
                    { ( nurl_print ` = bitcast ptr ` ) ( nurl_print pr2 ) ( nurl_print ` to i8*\n` ) }
                }
                : s vp2 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print vp2 )
                ( nurl_print ` = alloca ` ) ( nurl_print pt2 ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print pt2 )
                ( nurl_print ` ` ) ( nurl_print cv2 )
                ( nurl_print `, ` ) ( nurl_print pt2 )
                ( nurl_print `* ` ) ( nurl_print vp2 ) ( nurl_print `\n` )
                ( nurl_sym_def syms pv2 pt2 )
                ( nurl_sym_def syms ( nurl_str_cat pv2 `__ptr` ) vp2 )
            } {}

            = g_did_ret 0
            // Borrow checker (Phase 0c): a `??` arm `{` is a forward
            // join. A bare (block-less) arm leaves this armed; the
            // next arm re-arms it, and the post-loop disarm clears a
            // trailing bare arm's residue.
            ( bck_set_block_kind `match-arm` )
            : s arm_result ( gen_stmt lex syms cg )
            : s arm_type ( nurl_get_last_type )
            : s arm_lbl ( nurl_sym_get syms `__cur_lbl__` )
            : i arm_did_ret g_did_ret
            = arms_total + arms_total 1
            ? != 0 arm_did_ret { = arms_ret + arms_ret 1 } {}

            // Phase 2D arm-local fall-through drop — only safe when the arm
            // type is void (an arm-local heap object may back a value flowing
            // through to the phi consumer; freeing here would UAF).
            ? & & != 0 g_auto_drop_strings ( seq arm_type `void` ) == arm_did_ret 0
            { ( mem_drop_new_strings syms cg old_strs_m )
                ( mem_drop_new_struct_fields syms cg old_structs_m ) } {}
            ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}

            // Branch to end + record phi entry only when the arm didn't
            // return (a returning arm terminates with `ret`, so its block
            // is not a predecessor of end_label). Void-typed arms still
            // branch to end_label, so they need an `[ undef, %arm_lbl ]`
            // placeholder entry — otherwise the PHI's predecessor list
            // is missing entries and LLVM rejects the IR.
            ? == arm_did_ret 0 {
                ? ! ( seq arm_type `void` ) {
                    ? == phi_count 0 { = phi_type arm_type } {}
                    ? & != phi_count 0 ! ( seq arm_type phi_type ) { = phi_ok F } {}
                    : s entry ( nurl_str_cat `[ ` ( nurl_str_cat arm_result ( nurl_str_cat `, %` ( nurl_str_cat arm_lbl ` ]` ) ) ) )
                    = phi_entries ? == 0 ( nurl_str_len phi_entries )
                    entry
                    ( nurl_str_cat phi_entries ( nurl_str_cat `, ` entry ) )
                    = phi_count + phi_count 1
                } {
                    : s entry ( nurl_str_cat `[ undef, %` ( nurl_str_cat arm_lbl ` ]` ) )
                    = phi_entries ? == 0 ( nurl_str_len phi_entries )
                    entry
                    ( nurl_str_cat phi_entries ( nurl_str_cat `, ` entry ) )
                }
                ( nurl_print `  br label %` ) ( nurl_print end_label ) ( emit_dbg_eol )
            } {}

            // Continue to next arm (skipped for wildcard arms)
            ? != 0 ( nurl_str_len next_label ) {
                ( nurl_print next_label ) ( nurl_print `:\n` )
                ( nurl_sym_def syms `__cur_lbl__` next_label )
                = fallback_pred next_label
            } {
                // Wildcard arm — its body's terminated block is what the
                // post-loop fallback br lands in, so that br is dead.
                = fallback_pred ``
            }
        } {
            ( die lex `expected pattern identifier` )
        }
    }

    ( expect lex TT_RBRACE )  // expect '}'

    // Borrow checker: disarm — a trailing block-less arm would
    // otherwise leak `match-arm` onto the next sibling block (Phase
    // 0c) — then close the match with its `endmatch` marker (0d).
    ( bck_set_block_kind `` )
    ( bck_record `endmatch` `` bck_mline )

    // Exhaustive match check
    : i mtype_len ( nurl_str_len match_type )
    : s ename ? == ( nurl_str_get match_type 0 ) 37
    ( nurl_str_slice match_type 1 - mtype_len 1 )
    match_type
    ( check_exhaustive lex ename seen_variants has_wildcard syms )

    // Fallback br for the no-match case — only when an open `next_label:`
    // block is sitting at the bottom (i.e. the last arm was non-wildcard).
    // For wildcard-last, the trailing block was already terminated; emitting
    // a stray br after it would produce an unreachable unnamed block whose
    // edge into end_label isn't recorded in the phi — that breaks LLVM's
    // unreachable-block removal pass.
    ? != 0 ( nurl_str_len fallback_pred )
    { ( nurl_print `  br label %` ) ( nurl_print end_label ) ( emit_dbg_eol ) }
    {}

    // End label
    ( nurl_print end_label ) ( nurl_print `:\n` )
    ( nurl_sym_def syms `__cur_lbl__` end_label )

    // All arms ended in `^` AND the trailing fallback br landed here:
    // end_label is technically reachable but the match is exhaustive,
    // so no real path arrives. Emit unreachable + flag did_ret so the
    // function epilogue doesn't try to ret void into a non-void return.
    ? & & > arms_total 0 == arms_ret arms_total != 0 ( nurl_str_len fallback_pred )
    { ( emit_call_term `unreachable` ) = g_did_ret 1 } { = g_did_ret 0 }

    // Emit phi if every live arm produced a value of one consistent
    // non-void type.  Otherwise the match is treated as a statement.
    ? & & != 0 phi_count phi_ok ! ( seq phi_type `void` ) {
        : s final_reg ( nurl_cg_reg cg )
        : s phi_full phi_entries
        ? != 0 ( nurl_str_len fallback_pred ) {
            = phi_full ( nurl_str_cat phi_entries ( nurl_str_cat `, [ undef, %` ( nurl_str_cat fallback_pred ` ]` ) ) )
        } {}
        ( nurl_print `  ` ) ( nurl_print final_reg )
        ( nurl_print ` = phi ` ) ( nurl_print phi_type )
        ( nurl_print ` ` ) ( nurl_print phi_full ) ( nurl_print `\n` )
        ( nurl_set_last_type phi_type )
        ^ final_reg
    } {}
    ( nurl_set_last_type `void` )
    ^ `undef`
}

// ── For-each ~ var slice { body } ─────────────────────────────────
// Iterates over a slice { T*, i64 }, binding each element to var.
// Disambiguation: after '~', IDENT then IDENT → for-each (not while).

@ gen_foreach i lex i syms i cg → s {
    : s var_name ( nurl_lex_val lex )
    ( nurl_lex_advance lex )
    // BORROW.md Phase 6: snapshot the iterated container's name (when
    // it is a bare binding) before gen_expr consumes the token, so
    // the loop body can be checked for mutation of it.
    : s fe_cont ? ( is_ident_tok ( nurl_lex_type lex ) ) ( nurl_lex_val lex ) ``
    : s slice_val ( gen_expr lex syms cg )
    : s slice_ty ( nurl_get_last_type )
    // slice_ty = "{ T*, i64 }" — extract ptr_ty (T*) then elem_ty (T)
    : i slen ( nurl_str_len slice_ty )
    : s ptr_ty ( nurl_str_slice slice_ty 2 - - slen 7 2 )
    : s elem_ty ( nurl_str_slice ptr_ty 0 - ( nurl_str_len ptr_ty ) 1 )
    // Extract ptr and length from the slice struct
    : s ptr_val ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print ptr_val )
    ( nurl_print ` = extractvalue ` ) ( nurl_print slice_ty )
    ( nurl_print ` ` ) ( nurl_print slice_val ) ( nurl_print `, 0\n` )
    : s len_val ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print len_val )
    ( nurl_print ` = extractvalue ` ) ( nurl_print slice_ty )
    ( nurl_print ` ` ) ( nurl_print slice_val ) ( nurl_print `, 1\n` )
    // Alloca for index counter
    : s idx_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print idx_ptr )
    ( nurl_print ` = alloca i64\n` )
    ( nurl_print `  store i64 0, i64* ` ) ( nurl_print idx_ptr ) ( nurl_print `\n` )
    // Alloca for the loop element variable; bind in symtable
    : s elem_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print elem_ptr )
    ( nurl_print ` = alloca ` ) ( nurl_print elem_ty ) ( nurl_print `\n` )
    ( nurl_sym_def syms var_name elem_ty )
    ( nurl_sym_def syms ( nurl_str_cat var_name `__ptr` ) elem_ptr )
    // Labels
    : s lc ( nurl_cg_lbl cg `foreach_check` )
    : s lb ( nurl_cg_lbl cg `foreach_body` )
    : s le ( nurl_cg_lbl cg `foreach_exit` )
    ( nurl_print `  br label %` ) ( nurl_print lc ) ( emit_dbg_eol )
    // Check: idx < len
    ( emit ( nurl_str_cat lc `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lc )
    : s idx_cur ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print idx_cur )
    ( nurl_print ` = load i64, i64* ` ) ( nurl_print idx_ptr ) ( emit_dbg_eol )
    : s cond ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print cond )
    ( nurl_print ` = icmp slt i64 ` ) ( nurl_print idx_cur )
    ( nurl_print `, ` ) ( nurl_print len_val ) ( nurl_print `\n` )
    ( nurl_print `  br i1 ` ) ( nurl_print cond )
    ( nurl_print `, label %` ) ( nurl_print lb )
    ( nurl_print `, label %` ) ( nurl_print le ) ( emit_dbg_eol )
    // Body: load element at idx, store to var alloca, run block
    ( emit ( nurl_str_cat lb `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lb )
    : s gep ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print gep )
    ( nurl_print ` = getelementptr ` ) ( nurl_print elem_ty )
    ( nurl_print `, ` ) ( nurl_print ptr_ty )
    ( nurl_print ` ` ) ( nurl_print ptr_val )
    ( nurl_print `, i64 ` ) ( nurl_print idx_cur ) ( nurl_print `\n` )
    : s elem_val ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print elem_val )
    ( nurl_print ` = load ` ) ( nurl_print elem_ty )
    ( nurl_print `, ` ) ( nurl_print ptr_ty )
    ( nurl_print ` ` ) ( nurl_print gep ) ( nurl_print `\n` )
    ( nurl_print `  store ` ) ( nurl_print elem_ty ) ( nurl_print ` ` )
    ( nurl_print elem_val ) ( nurl_print `, ` )
    ( nurl_print ptr_ty ) ( nurl_print ` ` ) ( nurl_print elem_ptr ) ( nurl_print `\n` )
    // Scope foreach body (see gen_cond / gen_loop).
    : s old_strs_fe ``
    : s old_structs_fe ``
    : s old_user_fe ``
    ? != 0 g_auto_drop_strings
    { = old_strs_fe ( nurl_sym_get syms `__owned_strings__` )
        = old_structs_fe ( nurl_sym_get syms `__owned_struct_fields__` )
        = old_user_fe ( nurl_sym_get syms `__user_drops__` )
        ( nurl_sym_push syms )
    } {}
    = g_did_ret 0
    // Borrow checker (Phase 0c): a `~ x xs` body is a back-edge, and
    // (Phase 6) borrows the iterated container `xs` for the body's
    // duration — bck_iter_enter records it so gen_call rejects any
    // mutation of it inside the body; restored after the body.
    ( bck_set_block_kind `foreach` )
    : s fe_iter_saved ( bck_iter_enter fe_cont )
    ( gen_block_stmts lex syms cg )
    ( bck_iter_exit fe_iter_saved )
    ? == g_did_ret 0
    { ? != 0 g_auto_drop_strings
        { ( mem_drop_new_strings syms cg old_strs_fe )
            ( mem_drop_new_struct_fields syms cg old_structs_fe )
            ( mem_drop_new_user_drops syms cg old_user_fe ) } {}
        : s next_idx ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print next_idx )
        ( nurl_print ` = add i64 ` ) ( nurl_print idx_cur ) ( nurl_print `, 1\n` )
        ( nurl_print `  store i64 ` ) ( nurl_print next_idx )
        ( nurl_print `, i64* ` ) ( nurl_print idx_ptr ) ( nurl_print `\n` )
        ( nurl_print `  br label %` ) ( nurl_print lc ) ( emit_dbg_eol )
    }
    {}
    ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}
    ( emit ( nurl_str_cat le `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` le )
    ( nurl_set_last_type `void` )
    `undef`
}

// ── Loop ~ cond { body } ──────────────────────────────────────────

@ gen_loop i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    // For-each: ~ IDENT(var) IDENT(slice) { body }
    ? & == ( nurl_lex_type lex ) TT_IDENT == ( nurl_lex_peek_type lex ) TT_IDENT
    { ^ ( gen_foreach lex syms cg ) }
    {}

    // While loop `~ cond { body }`, or a complement expression used as
    // a statement (grammar alternative 3 — `~ expr`). Emit the
    // condition straight into `lc`, a re-enterable block, then look for
    // the `{`. The condition is therefore parsed exactly once and
    // evaluated once per iteration — there is no speculative parse
    // whose IR would have to be discarded, so a side-effecting
    // condition runs exactly (bodies + 1) times. If no `{` follows it
    // was a complement expression: `lc` stays as a harmless
    // single-predecessor block, the value is complemented, returned.
    : s lc ( nurl_cg_lbl cg `loop_check` )
    : s lb ( nurl_cg_lbl cg `loop_body` )
    : s le ( nurl_cg_lbl cg `loop_exit` )

    ( nurl_print `  br label %` ) ( nurl_print lc ) ( emit_dbg_eol )
    ( emit ( nurl_str_cat lc `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lc )
    : s cv ( gen_expr lex syms cg )
    : s cvt ( nurl_get_last_type )
    ? == ( nurl_lex_type lex ) TT_LBRACE
    {
        // It's a loop.
        // Narrow non-i1 integer loop conditions (see gen_cond).
        = cv ( coerce_to_i1 cv cvt cg )
        ( nurl_print `  br i1 ` ) ( nurl_print cv )
        ( nurl_print `, label %` ) ( nurl_print lb )
        ( nurl_print `, label %` ) ( nurl_print le ) ( emit_dbg_eol )
        ( emit ( nurl_str_cat lb `:` ) )
        // Scope the loop body so `:` bindings don't leak into the outer
        // `__owned_strings__` list (see gen_cond for the same reasoning).
        : s old_strs_lp ``
        : s old_structs_lp ``
        ? != 0 g_auto_drop_strings
        { = old_strs_lp ( nurl_sym_get syms `__owned_strings__` )
            = old_structs_lp ( nurl_sym_get syms `__owned_struct_fields__` )
            ( nurl_sym_push syms )
        } {}
        ( nurl_sym_def syms `__cur_lbl__` lb )
        = g_did_ret 0
        // Borrow checker (Phase 0c): a `~` while-body is a back-edge —
        // the analyze walk must iterate it to a fixpoint.
        ( bck_set_block_kind `loop` )
        ( gen_block_stmts lex syms cg )
        ? == g_did_ret 0
        { ? != 0 g_auto_drop_strings
            { ( mem_drop_new_strings syms cg old_strs_lp )
                ( mem_drop_new_struct_fields syms cg old_structs_lp ) } {}
            ( nurl_print `  br label %` ) ( nurl_print lc ) ( emit_dbg_eol )
        } {}
        ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}
        ( emit ( nurl_str_cat le `:` ) )
        ( nurl_sym_def syms `__cur_lbl__` le )
        ( nurl_set_last_type `void` )
        ^ `undef`
    }
    {
        // No block — a complement expression `~ cond` used as a
        // statement (grammar alternative 3). `cv` already holds the
        // operand value (emitted into `lc`); apply the complement and
        // return it. `lc` stays as a harmless single-predecessor block.
        : s res_c ( nurl_cg_reg cg )
        ? ( seq cvt `double` )
        { ( nurl_print `  ` ) ( nurl_print res_c )
            ( nurl_print ` = fneg double ` ) ( nurl_print cv ) ( nurl_print `\n` ) }
        { ( nurl_print `  ` ) ( nurl_print res_c )
            ( nurl_print ` = xor ` ) ( nurl_print cvt )
            ( nurl_print ` ` ) ( nurl_print cv ) ( nurl_print `, -1\n` ) }
        ( nurl_set_last_type cvt )
        ^ res_c
    }
}

// ── Defer ; { block } ─────────────────────────────────────────────
// Registers a block to be executed (LIFO) at function exit.
// Emits the block as a labelled basic block jumped over during
// normal execution; every exit path routes through the defer chain.

@ gen_defer i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s ldefer ( nurl_cg_lbl cg `defer` )
    : s lafter ( nurl_cg_lbl cg `after_defer` )
    : s prev_top ( nurl_sym_get syms `__defer_top__` )
    // Push this defer onto the chain (LIFO: new top)
    ( nurl_sym_def syms `__defer_top__` ldefer )
    = g_defer_count + g_defer_count 1
    // Skip over the defer block during normal execution
    ( nurl_print `  br label %` ) ( nurl_print lafter ) ( emit_dbg_eol )
    // Emit the defer block
    ( emit ( nurl_str_cat ldefer `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` ldefer )
    = g_did_ret 0
    ( gen_block_stmts lex syms cg )
    // After the defer block: chain to previous defer or to fn_cleanup
    ? == g_did_ret 0
    { ? != 0 ( nurl_str_len prev_top )
        { ( nurl_print `  br label %` ) ( nurl_print prev_top ) ( emit_dbg_eol ) }
        { : s fc ( nurl_sym_get syms `__fn_cleanup__` )
            ( nurl_print `  br label %` ) ( nurl_print fc ) ( emit_dbg_eol )
        }
    }
    {}
    // Resume normal execution after the defer block
    ( emit ( nurl_str_cat lafter `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lafter )
    = g_did_ret 0
    ( nurl_set_last_type `void` )
    `undef`
}

// ── Block expression { stmts... } ─────────────────────────────────

@ gen_block_expr i lex i syms i cg → s {
    : i bck_line ( nurl_lex_line lex )
    ( nurl_lex_advance lex )
    ( bck_block_enter bck_line )
    : s last `undef`
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        = last ( gen_stmt lex syms cg )
    }
    ( nurl_lex_advance lex )
    ( bck_block_exit )
    last
}

@ gen_block_stmts i lex i syms i cg → v {
    : i bck_line ( nurl_lex_line lex )
    ( expect lex TT_LBRACE )
    ( bck_block_enter bck_line )
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        ( gen_stmt lex syms cg )
    }
    ( expect lex TT_RBRACE )
    ( bck_block_exit )
}

// gen_block_ret: like gen_block_stmts but returns the last stmt value.
@ gen_block_ret i lex i syms i cg → s {
    : i bck_line ( nurl_lex_line lex )
    ( expect lex TT_LBRACE )
    // Borrow checker: a `{` opens a block — record the boundary and
    // descend a nesting level. The `block` row carries whatever the
    // read-accumulator holds, i.e. the controlling `?`/`~`/`??`
    // condition that was evaluated just before this arm.
    ( bck_block_enter bck_line )
    : s last `undef`
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        = last ( gen_stmt lex syms cg )
    }
    ( expect lex TT_RBRACE )
    ( bck_block_exit )
    last
}

// ── Memory ownership (Phase 1: slice-literal auto-drop, fn-scope) ──
// Sideband keys on symtab:
//   __owned_slices__     — space-separated binding names owning a slice buffer
//   __last_ident_name__  — name of the last identifier load (set by gen_ident)
// Lifecycle: init empty at fn entry; drop at each return path.

// Append `name` to the current scope's owned-slices list.
@ mem_own_add i syms s name → v {
    : s cur ( nurl_sym_get syms `__owned_slices__` )
    : s new ? == 0 ( nurl_str_len cur )
    name
    ( nurl_str_cat3 cur ` ` name )
    ( nurl_sym_def syms `__owned_slices__` new )
}

// True if `t` looks like a slice struct "{ T*, i64 }".
@ mem_is_slice_ty s t → b {
    & != 0 ( nurl_str_starts t `{ ` )
    >= ( nurl_str_find t `*, i64 }` ) 0
}

// Emit `free` for every binding in the owned list, skipping `skip_name`.
// If defers are active, skips entirely (defers may still reference slices).
// Does NOT clear the list — each return path emits its own set; paths are
// mutually exclusive at runtime.
@ mem_drop_owned i syms i cg s skip_name → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : s rest ( nurl_sym_get syms `__owned_slices__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s name ( str_first_word rest )
            = rest ( str_skip_word rest )
            ? ! ( seq name skip_name )
            { : s ty ( nurl_sym_get syms name )
                : s ptr ( nurl_sym_get syms ( nurl_str_cat name `__ptr` ) )
                // Slice type is always "{ <T>*, i64 }" (suffix ", i64 }" = 7 chars).
                // Extract <T>* = chars [2 .. len-7).
                : i tylen ( nurl_str_len ty )
                : s tptr ( nurl_str_slice ty 2 - tylen 9 )
                : s v ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print v )
                ( nurl_print ` = load ` ) ( nurl_print ty )
                ( nurl_print `, ` ) ( nurl_print ty )
                ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                : s dp ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print dp )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ty )
                ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `, 0\n` )
                : s raw ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print raw )
                ( nurl_print ` = bitcast ` ) ( nurl_print tptr )
                ( nurl_print ` ` ) ( nurl_print dp ) ( nurl_print ` to i8*\n` )
                ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print raw ) ( nurl_print `)` ) ( emit_dbg_eol )
            }
            {}
        }
    }
    {}
}

// ── Phase 2B: owned-string tracking (opt-in, gated on g_auto_drop_strings) ──
// `__owned_strings__` holds space-separated alloca-pointer names (e.g. %r12)
// of i8* bindings whose value was produced by an allocating runtime call
// (nurl_str_cat, nurl_read_file, ...). We free the loaded value at fn exit.

@ mem_own_add_str i syms s ptr → v {
    : s cur ( nurl_sym_get syms `__owned_strings__` )
    : s new ? == 0 ( nurl_str_len cur )
    ptr
    ( nurl_str_cat3 cur ` ` ptr )
    ( nurl_sym_def syms `__owned_strings__` new )
}

@ mem_drop_owned_strings i syms i cg s skip_ptr → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : s rest ( nurl_sym_get syms `__owned_strings__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s ptr ( str_first_word rest )
            = rest ( str_skip_word rest )
            ? ! ( seq ptr skip_ptr )
            { : s v ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print v )
                ( nurl_print ` = load i8*, i8** ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print v ) ( nurl_print `)` ) ( emit_dbg_eol )
            }
            {}
        }
    }
    {}
}

// ── Phase 2C / 2D: owned struct-field tracking (gated on g_auto_drop_strings)
// `__owned_struct_fields__` holds space-separated groups of SIX tokens:
//   <alloca_ptr> <outer_sname> <path> <kind> <leaf_sname> <leaf_idx>
// `path` is a dotted sequence of field indices from the outer struct root
// (e.g. `0` for a flat field, `0.1` for nested — Outer.field0.field1).
// `kind` ∈ { "str", "slice" }. `leaf_sname` / `leaf_idx` identify the
// struct that DIRECTLY contains the leaf field; used to recover slice
// element type (`<leaf_sname>__idx_<leaf_idx>__type`) at drop time.
// For flat paths leaf_sname == outer_sname and leaf_idx == path.
//
// At scope exit we load the outer struct and use LLVM's multi-index
// extractvalue to reach the leaf in one instruction (LLVM derives the
// intermediate struct types from the outer `%Name` type layout):
//   %v = load %Outer, %Outer* %ptr
//   %leaf = extractvalue %Outer %v, <path>      ; comma-separated indices
// For str: free the i8* directly. For slice: extractvalue 0 on the
// { T*, i64 }, bitcast to i8*, free.

// Turn a dotted path like "0.2.1" into ", 0, 2, 1" — the suffix used in
// LLVM's multi-index extractvalue. Empty path → "".
@ mem_path_to_indices s path → s {
    : i n ( nurl_str_len path )
    ? == n 0 { ^ `` } {}
    : s out `, `
    : i i 0
    ~ < i n {
        : i c ( nurl_str_get path i )
        ? == c 46
        { = out ( nurl_str_cat out `, ` ) }
        { = out ( nurl_str_cat out ( nurl_str_slice path i 1 ) ) }
        = i + i 1
    }
    ^ out
}

@ mem_own_add_struct_field i syms s ptr s sname s path s kind s leaf_sname s leaf_idx → v {
    : s cur ( nurl_sym_get syms `__owned_struct_fields__` )
    : s entry ( nurl_str_cat3 ptr ` ` sname )
    = entry ( nurl_str_cat3 entry ` ` path )
    = entry ( nurl_str_cat3 entry ` ` kind )
    = entry ( nurl_str_cat3 entry ` ` leaf_sname )
    = entry ( nurl_str_cat3 entry ` ` leaf_idx )
    : s new ? == 0 ( nurl_str_len cur )
    entry
    ( nurl_str_cat3 cur ` ` entry )
    ( nurl_sym_def syms `__owned_struct_fields__` new )
}

// Called after a let-binding's RHS gen_expr. If that expression was a
// named-struct aggregate literal with fresh-owned fields (signalled via
// `__last_agg_owned_fields__` — space-separated tokens of shape
// `<path>:<kind>:<leaf_sname>:<leaf_idx>`), register each for drop. vt
// must be a named-struct type "%Name"; anon/non-struct types skip.
@ mem_register_agg_owned_fields i syms s ptr s vt → v {
    : s idxs ( nurl_sym_get syms `__last_agg_owned_fields__` )
    ? & != 0 ( nurl_str_len idxs ) == ( nurl_str_get vt 0 ) 37
    { : s sname ( nurl_str_slice vt 1 - ( nurl_str_len vt ) 1 )
        : s rest idxs
        ~ != 0 ( nurl_str_len rest ) {
            : s tok ( str_first_word rest )
            = rest ( str_skip_word rest )
            // tok: <path>:<kind>:<leaf_sname>:<leaf_idx>
            : i c1 ( nurl_str_find tok `:` )
            : s path ( nurl_str_slice tok 0 c1 )
            : s after1 ( nurl_str_slice tok + c1 1 - - ( nurl_str_len tok ) c1 1 )
            : i c2 ( nurl_str_find after1 `:` )
            : s kind ( nurl_str_slice after1 0 c2 )
            : s after2 ( nurl_str_slice after1 + c2 1 - - ( nurl_str_len after1 ) c2 1 )
            : i c3 ( nurl_str_find after2 `:` )
            : s leaf_sname ( nurl_str_slice after2 0 c3 )
            : s leaf_idx ( nurl_str_slice after2 + c3 1 - - ( nurl_str_len after2 ) c3 1 )
            ( mem_own_add_struct_field syms ptr sname path kind leaf_sname leaf_idx )
        }
    }
    {}
    ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
}

// Shared per-entry drop IR. Emits load + extractvalue + nurl_free for one
// <ptr sname path kind leaf_sname leaf_idx> entry.
@ mem_emit_struct_field_drop i syms i cg s ptr s sname s path s kind s leaf_sname s leaf_idx → v {
    : s agg_ty ( nurl_str_cat `%` sname )
    : s idx_list ( mem_path_to_indices path )
    : s sv ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print sv )
    ( nurl_print ` = load ` ) ( nurl_print agg_ty )
    ( nurl_print `, ` ) ( nurl_print agg_ty )
    ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
    ? ( seq kind `str` )
    { : s fv ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print fv )
        ( nurl_print ` = extractvalue ` ) ( nurl_print agg_ty )
        ( nurl_print ` ` ) ( nurl_print sv ) ( nurl_print idx_list )
        ( nurl_print `\n` )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print fv ) ( nurl_print `)` ) ( emit_dbg_eol )
    }
    { : s slice_ty ( nurl_sym_get syms ( nurl_str_cat3 leaf_sname `__idx_` ( nurl_str_cat leaf_idx `__type` ) ) )
        : i slen ( nurl_str_len slice_ty )
        : s tptr ( nurl_str_slice slice_ty 2 - slen 9 )
        : s sv2 ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print sv2 )
        ( nurl_print ` = extractvalue ` ) ( nurl_print agg_ty )
        ( nurl_print ` ` ) ( nurl_print sv ) ( nurl_print idx_list )
        ( nurl_print `\n` )
        : s dp ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print dp )
        ( nurl_print ` = extractvalue ` ) ( nurl_print slice_ty )
        ( nurl_print ` ` ) ( nurl_print sv2 ) ( nurl_print `, 0\n` )
        : s raw ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print raw )
        ( nurl_print ` = bitcast ` ) ( nurl_print tptr )
        ( nurl_print ` ` ) ( nurl_print dp ) ( nurl_print ` to i8*\n` )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print raw ) ( nurl_print `)` ) ( emit_dbg_eol )
    }
}

@ mem_drop_owned_struct_fields i syms i cg → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : s rest ( nurl_sym_get syms `__owned_struct_fields__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s ptr ( str_first_word rest ) = rest ( str_skip_word rest )
            : s sname ( str_first_word rest ) = rest ( str_skip_word rest )
            : s path ( str_first_word rest ) = rest ( str_skip_word rest )
            : s kind ( str_first_word rest ) = rest ( str_skip_word rest )
            : s leaf_sname ( str_first_word rest ) = rest ( str_skip_word rest )
            : s leaf_idx ( str_first_word rest ) = rest ( str_skip_word rest )
            ( mem_emit_struct_field_drop syms cg ptr sname path kind leaf_sname leaf_idx )
        }
    }
    {}
}

// ── Phase 2D: arm-local delta drop ────────────────────────────────
// When an arm falls through (no `^ ret`) and its `nurl_sym_pop` is about
// to discard the arm scope, we must free owned bindings added DURING the
// arm or they leak. `mem_own_add_str` / `mem_own_add_struct_field` store
// the concatenation of the parent's list plus arm-local entries in the
// pushed scope's `__owned_strings__` / `__owned_struct_fields__`. To drop
// only the arm-local tail, snapshot the parent's list string before
// `nurl_sym_push`, then at fall-through skip that prefix (plus its
// trailing space, if non-empty) and iterate what remains.

@ mem_drop_new_strings i syms i cg s old_list → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : s cur ( nurl_sym_get syms `__owned_strings__` )
        : i old_len ( nurl_str_len old_list )
        : i cur_len ( nurl_str_len cur )
        ? > cur_len old_len
        { : i skip ? == old_len 0 0 + old_len 1
            : s rest ( nurl_str_slice cur skip - cur_len skip )
            ~ != 0 ( nurl_str_len rest ) {
                : s ptr ( str_first_word rest )
                = rest ( str_skip_word rest )
                : s v ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print v )
                ( nurl_print ` = load i8*, i8** ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print v ) ( nurl_print `)` ) ( emit_dbg_eol )
            }
        }
        {}
    }
    {}
}

@ mem_drop_new_struct_fields i syms i cg s old_list → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : s cur ( nurl_sym_get syms `__owned_struct_fields__` )
        : i old_len ( nurl_str_len old_list )
        : i cur_len ( nurl_str_len cur )
        ? > cur_len old_len
        { : i skip ? == old_len 0 0 + old_len 1
            : s rest ( nurl_str_slice cur skip - cur_len skip )
            ~ != 0 ( nurl_str_len rest ) {
                : s ptr ( str_first_word rest ) = rest ( str_skip_word rest )
                : s sname ( str_first_word rest ) = rest ( str_skip_word rest )
                : s path ( str_first_word rest ) = rest ( str_skip_word rest )
                : s kind ( str_first_word rest ) = rest ( str_skip_word rest )
                : s leaf_sname ( str_first_word rest ) = rest ( str_skip_word rest )
                : s leaf_idx ( str_first_word rest ) = rest ( str_skip_word rest )
                ( mem_emit_struct_field_drop syms cg ptr sname path kind leaf_sname leaf_idx )
            }
        }
        {}
    }
    {}
}

@ mem_own_add_user_drop i syms s ptr s vt → v {
    : s cur ( nurl_sym_get syms `__user_drops__` )
    : s entry ( nurl_str_cat3 ptr ` ` vt )
    : s new ? == 0 ( nurl_str_len cur )
    entry
    ( nurl_str_cat3 cur ` ` entry )
    ( nurl_sym_def syms `__user_drops__` new )
}

@ mem_drop_user_drops i syms i cg s skip_ptr → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : s rest ( nurl_sym_get syms `__user_drops__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s ptr ( str_first_word rest ) = rest ( str_skip_word rest )
            : s vt ( str_first_word rest ) = rest ( str_skip_word rest )
            ? ( seq ptr skip_ptr )
            {}
            { : s impl_key ( nurl_str_cat `drop##` vt )
                : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
                ? != 0 ( nurl_str_len impl_mangle_key )
                { : s impl_name ( nurl_str_cat `drop__` impl_mangle_key )
                    : s v ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print v )
                    ( nurl_print ` = load ` ) ( nurl_print vt ) ( nurl_print `, ` ) ( nurl_print vt )
                    ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                    ( nurl_print `  call void @` ) ( nurl_print impl_name )
                    ( nurl_print `(` ) ( nurl_print vt ) ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `)` ) ( emit_dbg_eol )
                }
                {}
            }
        }
    }
    {}
}

@ mem_drop_new_user_drops i syms i cg s old_list → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : s cur ( nurl_sym_get syms `__user_drops__` )
        : i old_len ( nurl_str_len old_list )
        : i cur_len ( nurl_str_len cur )
        ? > cur_len old_len
        { : i skip ? == old_len 0 0 + old_len 1
            : s rest ( nurl_str_slice cur skip - cur_len skip )
            ~ != 0 ( nurl_str_len rest ) {
                : s ptr ( str_first_word rest ) = rest ( str_skip_word rest )
                : s vt ( str_first_word rest ) = rest ( str_skip_word rest )
                : s impl_key ( nurl_str_cat `drop##` vt )
                : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
                ? != 0 ( nurl_str_len impl_mangle_key )
                { : s impl_name ( nurl_str_cat `drop__` impl_mangle_key )
                    : s v ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print v )
                    ( nurl_print ` = load ` ) ( nurl_print vt ) ( nurl_print `, ` ) ( nurl_print vt )
                    ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                    ( nurl_print `  call void @` ) ( nurl_print impl_name )
                    ( nurl_print `(` ) ( nurl_print vt ) ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `)` ) ( emit_dbg_eol )
                }
                {}
            }
        }
        {}
    }
    {}
}

// ── Borrow checker — analysis substrate (BORROW.md Phase 0) ─────────
//
// The borrow checker is a diagnostic-only pass: it inspects the
// program and may emit `error:` / `warning:`, but it NEVER emits IR.
// A borrow-clean program therefore compiles to byte-identical IR
// whether --borrowck is on or off, and the bootstrap fixed point is
// unaffected. Every entry point below is a no-op when g_borrowck is 0.
//
// Phase 0 lands the substrate only — there are no borrow rules yet,
// so even with --borrowck on the pass emits nothing. Later phases
// (move checking, alias/double-free, escape analysis) hang their
// rules off the per-function CFG + ownership lattice built here.

// ── Phase 0b: per-function statement-list capture ──────────────────
//
// As each function body is parsed, guarded hooks in the gen_* walk
// append a flat statement list into g_bck. Each record is a single
// tab-delimited line:
//
//   <kind> \t <wname> \t <reads> \t <line> \t <depth>
//
//   kind   — let | assign | ret | expr | block | endblock
//            | cond | endcond | match | endmatch  (Phase 0d markers)
//            | move  (Phase 1 — wname is the consumed binding)
//   wname  — the binding written (let/assign); for a `block` marker
//            the block's kind (Phase 0c — see below); else empty
//   reads  — space-separated identifiers read by the statement; for a
//            `cond`/`match` marker the controlling condition / match
//            scrutinee reads; for a `loop`/`foreach` block the loop
//            condition / iterated-slice reads; empty for `cond-then` /
//            `cond-else` / `match-arm` / `plain` block rows
//   line   — 1-based source line
//   depth  — block-nesting depth (function body is depth 1)
//
// Records are newline-separated. The capture is inert unless
// --borrowck is set, and never emits IR, so the bootstrap fixed point
// is unaffected.
//
// Phase 0c — block kinds. Every `block` row carries, in its wname
// field, the kind of `{` that opened it, so the analyze walk can tell
// a back-edge from a forward join without re-deriving control flow:
//
//   cond-then  — the then-arm of a `?`            (forward join)
//   cond-else  — the else-arm of a `?`            (forward join)
//   match-arm  — one arm of a `??` match          (forward join)
//   loop       — the body of a `~` while-loop     (back-edge, fixpoint)
//   foreach    — the body of a `~ x : T xs` loop  (back-edge, fixpoint)
//   plain      — function body / defer / bare `{ }` block-expr
//
// Phase 0d — structural markers + the analyze walk. `?` and `??`
// group several arm-blocks (and bare, block-less arms), and plain
// block adjacency cannot say which arms belong to which construct —
// `? a {t} bare` followed by `? b bare {e}` puts a lone `cond-then`
// next to a lone `cond-else` that belong to different `?`s. gen_cond
// and gen_match therefore bracket each construct with explicit
// `cond`/`endcond` and `match`/`endmatch` rows. These do NOT move the
// block-depth counter (only `block`/`endblock` do); they are a second,
// independently balanced bracket system the analyze walk uses to scope
// a conditional / match and find its direct-child arm blocks while
// skipping nested constructs. bck_analyze then threads the ownership
// lattice through this tree.
//
// Known Phase 0 imprecision (refined in Phase 1): a closure literal's
// body is parsed through the same gen_block_ret path, so its
// statements land inline in the enclosing function's list — and a
// bare closure literal used directly as a `?`/`??` arm has its body
// block tagged with that arm's kind rather than `plain`. Harmless
// while there are no rules; Phase 1 must segregate closure scopes.

// Reset the per-function capture state. Called at function entry.
@ bck_fn_begin → v {
    ? != g_borrowck 0 {
        ( nurl_sym_def g_bck `stmts` `` )
        ( nurl_sym_def g_bck `reads` `` )
        ( nurl_sym_def g_bck `pending_kind` `` )
        ( nurl_sym_def g_bck `pmoves` `` )
        = g_bck_depth 0
    } {}
}

// Note that the current statement reads identifier `name`. Hooked
// into gen_ident, so it fires for every value-position identifier.
@ bck_note_read s name → v {
    ? & != g_borrowck 0 == g_bck_closure_depth 0 {
        : s cur ( nurl_sym_get g_bck `reads` )
        ( nurl_sym_def g_bck `reads`
            ? == 0 ( nurl_str_len cur ) name ( nurl_str_cat3 cur ` ` name ) )
    } {}
}

// Append one statement record, then clear the read accumulator so the
// next statement starts fresh.
@ bck_record s kind s wname i line → v {
    ? & != g_borrowck 0 == g_bck_closure_depth 0 {
        : s reads ( nurl_sym_get g_bck `reads` )
        : s head ( nurl_str_cat4 kind `\t` wname `\t` )
        : s body ( nurl_str_cat4 head reads `\t` ( nurl_str_int line ) )
        : s rec ( nurl_str_cat3 body `\t` ( nurl_str_int g_bck_depth ) )
        : s cur ( nurl_sym_get g_bck `stmts` )
        ( nurl_sym_def g_bck `stmts`
            ? == 0 ( nurl_str_len cur ) rec ( nurl_str_cat3 cur `\n` rec ) )
        ( nurl_sym_def g_bck `reads` `` )
    } {}
}

// ── Phase 1/2: move-site capture ───────────────────────────────────
//
// A *move* consumes an owned binding. There are two move sources:
//
//   Phase 1 — a bare-identifier argument passed to a `*_free`
//   destructor (the typed NURL heap destructors `vec_free`,
//   `string_free`, … but NOT raw `nurl_free`, which frees `*T`/i8*
//   FFI memory that BORROW.md leaves unchecked). gen_call detects it.
//
//   Phase 2 — a binding-to-binding copy `: T b a` of an owned heap
//   value. `b` becomes the value's owner; `a` is moved. This makes
//   the silent-alias double-free (`: T b a` then both freed)
//   impossible: any later use of `a` is a use-after-move. gen_let
//   detects it. Scalars (Copy) and parameters (borrowed) are excluded.
//
// Either way the consumed binding is stashed in `pmoves`; gen_stmt
// flushes the stash into `move` rows AFTER the enclosing statement's
// own row, so the consuming statement itself — which legitimately
// reads the binding one last time — is not flagged.
//
// A `move` row is `move \t <binding> \t \t <line> \t <depth>`. The
// analyze walk transitions the binding Owned -> Moved; a `let` / `=`
// of the binding revives it to Owned.

// True when `name` ends with the literal suffix `_free` — i.e. the
// callee is a typed heap destructor. NB: this predicate must NOT
// itself be named with a `_free` (or `..._is_free`) suffix — the
// Phase 1 move rule keys on a `_free`-suffixed callee, so such a
// helper would be misread as a destructor and flag its own
// bare-identifier argument as moved (a false positive in nurlc.nu).
@ bck_is_destructor_name s name → b {
    : i len ( nurl_str_len name )
    ? < len 5 { ^ F } {}
    ( seq ( nurl_str_slice name - len 5 5 ) `_free` )
}

// ── Borrow checker — iterator invalidation (BORROW.md Phase 6) ─────
//
// A `~ x xs { ... }` foreach loop borrows the container `xs` for the
// body's duration — gen_foreach snapshots the buffer pointer + length
// once, up front, so a `vec_push` that reallocs (or a `vec_free`)
// inside the body leaves the loop cursor pointing at freed memory.
// gen_foreach brackets the body with bck_iter_enter / bck_iter_exit,
// pushing the iterated binding onto `g_bck`'s `iter_containers` list
// (a save/restore stack — nested foreach loops compose). gen_call
// then rejects mutating that container from inside the body.

// True when `fname` is a stdlib container operation that mutates its
// receiver's backing buffer (reallocates, frees, or rewrites
// elements) — the receiver is always the first value argument.
@ bck_is_container_mutator s fname → b {
    ( str_contains_word
        `vec_push vec_insert vec_remove vec_pop vec_clear vec_set vec_set_len vec_reserve vec_shrink_to_fit vec_extend vec_free vec_free_with vec_swap vec_reverse`
        fname )
}

// Push `cont` onto the iterated-container stack; return the prior
// value so the caller can restore it once the loop body is parsed.
// No-op (returns ``) when --borrowck is off.
@ bck_iter_enter s cont → s {
    ? == g_borrowck 0 { ^ `` } {}
    : s saved ( nurl_sym_get g_bck `iter_containers` )
    ? != 0 ( nurl_str_len cont )
    { ( nurl_sym_def g_bck `iter_containers`
        ? == 0 ( nurl_str_len saved ) cont
        ( nurl_str_cat3 saved ` ` cont ) ) }
    {}
    saved
}

@ bck_iter_exit s saved → v {
    ? == g_borrowck 0 {} { ( nurl_sym_def g_bck `iter_containers` saved ) }
}

// True when LLVM type `lty` is a heap-owned aggregate the borrow
// checker tracks — a named struct/enum (`%Name`) or an anonymous
// aggregate / slice (`{ … }`). Pointers (`*T`, trailing `*`) are
// FFI-shaped and unchecked; raw `i8*` strings are excluded for now
// (their auto-drop double-free is already conservatively avoided —
// explicit string-alias checking is a Phase 2 follow-up); scalars
// (`i64` / `i1` / `double` / `iN`) are Copy and never move.
@ bck_is_heap_lty s lty → b {
    : i len ( nurl_str_len lty )
    ? == 0 len { ^ F } {}
    ? == ( nurl_str_get lty - len 1 ) 42 { ^ F } {}
    : i c0 ( nurl_str_get lty 0 )
    | == c0 37 == c0 123
}

// Phase 2: an immutable `: T b a` whose RHS is a bare identifier
// naming a non-parameter heap binding moves `a` — its ownership
// passes to `b`. The new binding must be immutable: a `: ~` copy is
// the cursor idiom (a mutable working alias that walks a structure
// while the source stays the owner — e.g. toml.nu's `current`), a
// borrow, not a move. Distinguishing borrow from move in the general
// case is the job of a later reference-surface phase; until then the
// immutability of the destination is the heuristic.
@ bck_let_alias i syms b is_mut i rhs_tt s rhs_val s vt i line → v {
    ? & & & ! is_mut ( is_ident_tok rhs_tt ) ( bck_is_heap_lty vt )
        ! ( str_contains_word ( nurl_sym_get syms `__fn_param_names__` ) rhs_val )
    { ( bck_stash_move rhs_val line ) }
    {}
}

// Stash `name` (consumed at `line`) for the current statement.
@ bck_stash_move s name i line → v {
    ? & != g_borrowck 0 == g_bck_closure_depth 0 {
        : s cur ( nurl_sym_get g_bck `pmoves` )
        : s add ( nurl_str_cat3 name ` ` ( nurl_str_int line ) )
        ( nurl_sym_def g_bck `pmoves`
            ? == 0 ( nurl_str_len cur ) add ( nurl_str_cat3 cur ` ` add ) )
    } {}
}

// Drain the per-statement move stash into `move` rows. Called by
// gen_stmt once the enclosing statement's own record is in place.
@ bck_flush_moves → v {
    ? & != g_borrowck 0 == g_bck_closure_depth 0 {
        : ~ s rest ( nurl_sym_get g_bck `pmoves` )
        ( nurl_sym_def g_bck `pmoves` `` )
        // A statement that recorded no row of its own leaves stray
        // reads in the accumulator — clear them so `move` rows, which
        // carry no reads, are not mislabelled.
        ( nurl_sym_def g_bck `reads` `` )
        ~ != 0 ( nurl_str_len rest ) {
            : s nm ( str_first_word rest )
            = rest ( str_skip_word rest )
            : s ln ( str_first_word rest )
            = rest ( str_skip_word rest )
            ( bck_record `move` nm ( nurl_str_to_int ln ) )
        }
    } {}
}

// ── Phase 0c: block-kind tagging ───────────────────────────────────
//
// A bare `block` row says "a `{` opened here" but not WHAT kind of
// block — and a sound analysis must tell a `~`-loop body (a back-edge
// the lattice has to iterate to a fixpoint) apart from a `?`/`??` arm
// (a forward join). gen_cond / gen_loop / gen_foreach / gen_match each
// arm a `pending_kind` slot just before they invoke a block parser;
// the next bck_block_enter consumes it into the `block` row's wname
// field, then disarms the slot. A block parser reached with no armed
// kind (function body, defer block, bare `{ }` block-expr) records
// `plain`.
//
// The slot is one-shot: gen_cond/gen_match also disarm it after their
// arms so a bare-expression arm (which opens no block) cannot leak its
// kind onto an unrelated sibling block. gen_loop/gen_foreach need no
// disarm — their body parser always opens a block, always consuming.
@ bck_set_block_kind s kind → v {
    ? & != g_borrowck 0 == g_bck_closure_depth 0
        { ( nurl_sym_def g_bck `pending_kind` kind ) } {}
}

// Block-boundary markers. enter records a `block` row (carrying any
// pending reads — i.e. the controlling `?`/`~`/`??` condition — in the
// reads field, and the armed block kind in the wname field) then
// descends a level; exit ascends then records `endblock`.
@ bck_block_enter i line → v {
    ? & != g_borrowck 0 == g_bck_closure_depth 0 {
        : s kind ( nurl_sym_get g_bck `pending_kind` )
        ( bck_record `block`
            ? == 0 ( nurl_str_len kind ) `plain` kind
            line )
        ( nurl_sym_def g_bck `pending_kind` `` )
        = g_bck_depth + g_bck_depth 1
    } {}
}

@ bck_block_exit → v {
    ? & != g_borrowck 0 == g_bck_closure_depth 0 {
        ? > g_bck_depth 0 { = g_bck_depth - g_bck_depth 1 } {}
        ( bck_record `endblock` `` 0 )
    } {}
}

// ── Phase 0d: ownership lattice + the analyze walk ─────────────────
//
// The lattice each binding's state moves through:
//
//   Uninit < Owned < { Moved, BorrowedShared, BorrowedMut } < Invalid
//
// with MaybeMoved sitting above Owned/Moved as the join of a value
// moved on one control-flow path and live on another. The join
// (bck_join) is the least upper bound used at every forward merge;
// Uninit is the bottom element, Invalid the top.
//
// Phase 0d lands the lattice + the structured analyze walk and
// nothing else. The walk threads a per-binding state map through the
// CFG — sequential flow, `?`/`??` fork-and-join, `~` loop back-edge
// to a fixpoint — but carries NO rules: it transitions a binding only
// on its `let` (Uninit -> Owned) and emits zero diagnostics. Phases
// 1+ hang move / alias / escape rules off this walk.
: i BCK_UNINIT 0
: i BCK_OWNED 1
: i BCK_MOVED 2
: i BCK_BORROWED_SHARED 3
: i BCK_BORROWED_MUT 4
: i BCK_MAYBE_MOVED 5
: i BCK_INVALID 6

// Lattice join — least upper bound of two per-binding states meeting
// at a control-flow merge point.
@ bck_join i a i b → i {
    ? == a b { ^ a } {}
    ? | == a BCK_INVALID == b BCK_INVALID { ^ BCK_INVALID } {}
    // Owned and Uninit are both "not moved here"; Moved and MaybeMoved
    // are "moved-ish". Any merge of a not-moved state with a moved-ish
    // one — or of two differing moved-ish states — is a conditional
    // move: MaybeMoved (which the use-after-move rule does NOT flag,
    // so a binding moved on only one branch never false-positives).
    // Two differing not-moved states (Owned vs Uninit) settle to
    // Owned. Crucially Uninit-joined-with-Moved is MaybeMoved, NOT
    // Moved — a parameter / match-payload binding that is Uninit in
    // the walk's state must not be reported as definitely moved just
    // because one branch consumed it.
    : b a_mv | == a BCK_MOVED == a BCK_MAYBE_MOVED
    : b b_mv | == b BCK_MOVED == b BCK_MAYBE_MOVED
    : b a_nm | == a BCK_OWNED == a BCK_UNINIT
    : b b_nm | == b BCK_OWNED == b BCK_UNINIT
    ? & a_mv b_mv { ^ BCK_MAYBE_MOVED } {}
    ? & a_mv b_nm { ^ BCK_MAYBE_MOVED } {}
    ? & a_nm b_mv { ^ BCK_MAYBE_MOVED } {}
    ? & a_nm b_nm { ^ BCK_OWNED } {}
    // Borrow-state disagreements are not produced until a later phase.
    BCK_INVALID
}

// ── Per-binding state — a space-separated `name=digit` map ─────────
// The analysis analogue of the mem_* owned-resource lists, but it
// records a lattice digit per binding (not mere membership) and is
// forked / joined at branches rather than scoped on a stack.

// Name part of a `name=digit` token (all but the last 2 chars).
// Every path returns a fresh owned string so callers free it once.
@ bck_tok_name s tok → s {
    : i len ( nurl_str_len tok )
    ? < len 2 { ^ ( nurl_str_cat tok `` ) } {}
    ( nurl_str_slice tok 0 - len 2 )
}

// Lattice digit of a `name=digit` token — its last character.
@ bck_tok_val s tok → i {
    : i len ( nurl_str_len tok )
    ? < len 1 { ^ BCK_UNINIT } {}
    - ( nurl_str_get tok - len 1 ) 48
}

// State lookup — BCK_UNINIT when the binding is absent.
@ bck_st_get s state s name → i {
    : ~ s rest state
    ~ != 0 ( nurl_str_len rest ) {
        : s tok ( str_first_word rest )
        = rest ( str_skip_word rest )
        ? ( seq ( bck_tok_name tok ) name ) { ^ ( bck_tok_val tok ) } {}
    }
    BCK_UNINIT
}

// State update — a new state with `name` set to `val` (any prior
// entry dropped; the binding lands at the end). Every `= out ...`
// builds a fresh string rather than aliasing the loop-local `tok`,
// which would be a double-free once both are auto-dropped.
@ bck_st_set s state s name i val → s {
    : ~ s out ( nurl_str_cat `` `` )
    : ~ s rest state
    ~ != 0 ( nurl_str_len rest ) {
        : s tok ( str_first_word rest )
        = rest ( str_skip_word rest )
        ? ( seq ( bck_tok_name tok ) name ) {} {
            = out ? == 0 ( nurl_str_len out )
                ( nurl_str_cat tok `` )
                ( nurl_str_cat3 out ` ` tok )
        }
    }
    : s nt ( nurl_str_cat3 name `=` ( nurl_str_int val ) )
    ? == 0 ( nurl_str_len out ) { ^ nt } {}
    ( nurl_str_cat3 out ` ` nt )
}

// State join — least upper bound of two states, binding by binding.
// A binding present on only one side joins against BCK_UNINIT on the
// other (and bck_join of UNINIT with x is x, so it carries through).
// `out` starts fresh and every `= out ...` builds a fresh string —
// aliasing a loop-local would double-free at auto-drop.
@ bck_join_state s a s b → s {
    : ~ s out ( nurl_str_cat `` `` )
    : ~ s rest a
    ~ != 0 ( nurl_str_len rest ) {
        : s tok ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s nm ( bck_tok_name tok )
        : i vj ( bck_join ( bck_tok_val tok ) ( bck_st_get b nm ) )
        : s nt ( nurl_str_cat3 nm `=` ( nurl_str_int vj ) )
        = out ? == 0 ( nurl_str_len out )
            ( nurl_str_cat nt `` )
            ( nurl_str_cat3 out ` ` nt )
    }
    : ~ s rest2 b
    ~ != 0 ( nurl_str_len rest2 ) {
        : s tok ( str_first_word rest2 )
        = rest2 ( str_skip_word rest2 )
        ? == BCK_UNINIT ( bck_st_get a ( bck_tok_name tok ) ) {
            = out ? == 0 ( nurl_str_len out )
                ( nurl_str_cat tok `` )
                ( nurl_str_cat3 out ` ` tok )
        } {}
    }
    out
}

// ── Record access ─────────────────────────────────────────────────
// bck_explode splits the captured statement list into individually
// addressable rows r0..r<n-1> on g_bck and records the count in `rn`.

@ bck_rec i idx → s {
    ( nurl_sym_get g_bck ( nurl_str_cat `r` ( nurl_str_int idx ) ) )
}

// idx-th tab-delimited field of a record (0=kind .. 4=depth).
@ bck_field s rec i idx → s {
    : i len ( nurl_str_len rec )
    : ~ i start 0
    : ~ i fno 0
    : ~ i pos 0
    ~ < pos len {
        ? == ( nurl_str_get rec pos ) 9 {
            ? == fno idx { ^ ( nurl_str_slice rec start - pos start ) } {}
            = fno + fno 1
            = start + pos 1
        } {}
        = pos + pos 1
    }
    ? == fno idx { ^ ( nurl_str_slice rec start - len start ) } {}
    // No such field — return a fresh empty string (consistent owned
    // return so callers free the result exactly once).
    ( nurl_str_cat `` `` )
}

@ bck_explode → i {
    : s txt ( nurl_sym_get g_bck `stmts` )
    : i len ( nurl_str_len txt )
    : ~ i start 0
    : ~ i n 0
    : ~ i pos 0
    ~ < pos len {
        ? == ( nurl_str_get txt pos ) 10 {
            ( nurl_sym_def g_bck ( nurl_str_cat `r` ( nurl_str_int n ) )
                ( nurl_str_slice txt start - pos start ) )
            = n + n 1
            = start + pos 1
        } {}
        = pos + pos 1
    }
    ? > len start {
        ( nurl_sym_def g_bck ( nurl_str_cat `r` ( nurl_str_int n ) )
            ( nurl_str_slice txt start - len start ) )
        = n + n 1
    } {}
    ( nurl_sym_def g_bck `rn` ( nurl_str_int n ) )
    n
}

// Index of the close marker matching the open marker at `idx`. The
// three bracket systems (block/endblock, cond/endcond, match/endmatch)
// are each independently balanced, so counting only the requested
// pair steps over any nested constructs of the other two kinds.
@ bck_match_close i idx s openk s closek → i {
    : i n ( nurl_str_to_int ( nurl_sym_get g_bck `rn` ) )
    : ~ i d 1
    : ~ i j + idx 1
    ~ & < j n > d 0 {
        : s k ( bck_field ( bck_rec j ) 0 )
        ? ( seq k openk ) { = d + d 1 } {}
        ? ( seq k closek ) { = d - d 1 } {}
        ? == d 0 { ^ j } {}
        = j + j 1
    }
    j
}

// ── Phase 1: the use-after-move rule ──────────────────────────────

// Emit `file:line: warning: use of moved value`. The analyze walk
// runs after the function is fully parsed, so `lex` no longer points
// at the use site — the line is carried explicitly and the filename
// is stashed on g_bck by borrowck_fn_end. Deduplicated per (line,
// name) via `warnset` so a loop body's fixpoint re-walk does not
// repeat the same warning.
@ bck_diag s name i useline → v {
    : s tag ( nurl_str_cat3 ( nurl_str_int useline ) `:` name )
    : s ws ( nurl_sym_get g_bck `warnset` )
    ? ( str_contains_word ws tag ) {} {
        ( nurl_sym_def g_bck `warnset`
            ? == 0 ( nurl_str_len ws ) tag ( nurl_str_cat3 ws ` ` tag ) )
        : s ml ( nurl_sym_get g_bck ( nurl_str_cat `ml_` name ) )
        : s loc ( nurl_str_cat3 ( nurl_sym_get g_bck `file` ) `:`
            ( nurl_str_int useline ) )
        : s msg ( nurl_str_cat4 `: warning: use of moved value '` name
            `' - it was consumed at line ` ( nurl_str_cat3 ml
            ` (pass a fresh value or rebind it before reuse)` `` ) )
        ( nurl_eprintln ( nurl_str_cat loc msg ) )
    }
}

// Flag any read of a definitely-Moved binding as a use-after-move.
// MaybeMoved (a conditional move at a CFG join) is deliberately NOT
// flagged — erroring only on a definite move keeps this first cut
// false-positive-free (BORROW.md watch #3: warn before you promote).
@ bck_check_moved_reads s reads i line s state → v {
    : ~ s rest reads
    ~ != 0 ( nurl_str_len rest ) {
        : s w ( str_first_word rest )
        = rest ( str_skip_word rest )
        ? == BCK_MOVED ( bck_st_get state w ) { ( bck_diag w line ) } {}
    }
}

// ── The analyze walk ──────────────────────────────────────────────
// bck_walk_seq threads `state` through the records in [lo, hi):
// sequential rows update the state; `?`/`??` fork the entry state
// across arms and join the results; `~` loops re-enter their body to
// a fixpoint. It returns the state holding at `hi`. Phase 1: every
// row's reads are checked for use-after-move before its writes apply.
@ bck_walk_seq i lo i hi s state → s {
    : ~ s st ( nurl_str_cat state `` )
    : ~ i p lo
    ~ < p hi {
        : s rec ( bck_rec p )
        : s kind ( bck_field rec 0 )
        : ~ b done F
        // Phase 1: a read of a Moved binding is a use-after-move.
        // Checked before this row's own writes so a consuming call
        // (move flushed AFTER it) reads its arg while still Owned.
        ( bck_check_moved_reads ( bck_field rec 2 )
            ( nurl_str_to_int ( bck_field rec 3 ) ) st )
        ? ( seq kind `let` ) {
            // A `let` (re)binds the name — Owned, reviving a Moved one.
            = st ( bck_st_set st ( bck_field rec 1 ) BCK_OWNED )
            = p + p 1
            = done T
        } {}
        ? & ! done ( seq kind `assign` ) {
            // `= x ...` gives x a fresh value — Owned, reviving x.
            = st ( bck_st_set st ( bck_field rec 1 ) BCK_OWNED )
            = p + p 1
            = done T
        } {}
        ? & ! done ( seq kind `move` ) {
            // A consumed binding: Owned -> Moved; remember where.
            : s mvn ( bck_field rec 1 )
            = st ( bck_st_set st mvn BCK_MOVED )
            ( nurl_sym_def g_bck ( nurl_str_cat `ml_` mvn )
                ( bck_field rec 3 ) )
            = p + p 1
            = done T
        } {}
        ? & ! done ( seq kind `cond` ) {
            : i ec ( bck_match_close p `cond` `endcond` )
            = st ( bck_handle_cond p ec st )
            = p + ec 1
            = done T
        } {}
        ? & ! done ( seq kind `match` ) {
            : i em ( bck_match_close p `match` `endmatch` )
            = st ( bck_handle_match p em st )
            = p + em 1
            = done T
        } {}
        ? & ! done ( seq kind `block` ) {
            : i eb ( bck_match_close p `block` `endblock` )
            : s bk ( bck_field rec 1 )
            ? | ( seq bk `loop` ) ( seq bk `foreach` ) {
                = st ( bck_loop + p 1 eb st )
            } {
                = st ( bck_walk_seq + p 1 eb st )
            }
            = p + eb 1
            = done T
        } {}
        // ret / expr / stray end-marker — reads already checked above
        ? ! done { = p + p 1 } {}
    }
    st
}

// `?` — walk the then-arm and the else-arm each from the conditional's
// entry state, then join. A block-less (bare) arm contributes the
// entry state unchanged. Nested `cond`/`match` inside a bare arm are
// stepped over wholesale so their arm-blocks are not mistaken for this
// conditional's arms.
@ bck_handle_cond i ci i ec s state → s {
    : ~ s s_then state
    : ~ s s_else state
    : ~ i j + ci 1
    ~ < j ec {
        : s rec ( bck_rec j )
        : s k ( bck_field rec 0 )
        : ~ b adv F
        ? ( seq k `cond` ) {
            = j + ( bck_match_close j `cond` `endcond` ) 1
            = adv T
        } {}
        ? & ! adv ( seq k `match` ) {
            = j + ( bck_match_close j `match` `endmatch` ) 1
            = adv T
        } {}
        ? & ! adv ( seq k `block` ) {
            : i eb ( bck_match_close j `block` `endblock` )
            : s bk ( bck_field rec 1 )
            ? ( seq bk `cond-then` )
                { = s_then ( bck_walk_seq + j 1 eb state ) } {}
            ? ( seq bk `cond-else` )
                { = s_else ( bck_walk_seq + j 1 eb state ) } {}
            = j + eb 1
            = adv T
        } {}
        ? ! adv { = j + j 1 } {}
    }
    ( bck_join_state s_then s_else )
}

// `??` — Phase 1 does NOT descend into match arms. A `??` arm binds
// payload variables (`T v -> ...`) that have no `let` row, so the
// flat name-keyed state cannot tell an arm's `v` from a same-named
// binding in an enclosing scope — analysing the arm would conflate
// them and false-positive. The whole match is therefore treated as a
// state-preserving black box: its scrutinee is still move-checked (on
// the `match` row, before this is called), but nothing inside the
// arms is. Use-after-move *within* a `??` arm is a known Phase 1 gap
// — closing it needs scope-qualified state (a later phase).
@ bck_handle_match i mi i em s state → s {
    ( nurl_str_cat state `` )
}

// `~` loop — the body carries a back-edge, so re-enter it until the
// state at the loop head stops changing (the join of the head state
// with the body's exit state). The 16-iteration cap is a safety
// bound; the height-7 lattice converges in far fewer.
@ bck_loop i lo i hi s pre → s {
    : ~ s head ( nurl_str_cat pre `` )
    : ~ i iter 0
    : ~ b done F
    ~ & ! done < iter 16 {
        : s post ( bck_walk_seq lo hi head )
        : s merged ( bck_join_state head post )
        // Copy `merged` into `head` — aliasing the loop-local `merged`
        // would double-free it (iteration drop + function-exit drop).
        ? ( seq merged head ) { = done T } { = head ( nurl_str_cat merged `` ) }
        = iter + iter 1
    }
    head
}

// bck_analyze: consume the per-function statement list captured by
// the gen_* hooks — explode it into addressable rows, then thread the
// ownership lattice through the whole function. The walk emits a
// use-after-move warning per Moved read. `params` (space-separated)
// seed the initial state as Owned: a parameter moved on one branch of
// a `?` then joins to MaybeMoved (not Moved) at the merge, rather than
// joining a bare Uninit on the other branch straight back to Moved.
@ bck_analyze s params → v {
    ( nurl_sym_def g_bck `warnset` `` )
    : i n ( bck_explode )
    : ~ s seed ``
    : ~ s prest params
    ~ != 0 ( nurl_str_len prest ) {
        : s pn ( str_first_word prest )
        = prest ( str_skip_word prest )
        = seed ( bck_st_set seed pn BCK_OWNED )
    }
    // Walk from the seeded state. n == 0 (no records) walks nothing.
    : s final ( bck_walk_seq 0 n seed )
    // `final` is the function's exit state; the walk inspects it no
    // further. Reference it in a void `?` so the body type-checks as
    // `v` without a spurious unused binding.
    ? != 0 ( nurl_str_len final ) {} {}
}

// borrowck_fn_end: called from gen_fn_decl_concrete once a function
// body is fully parsed — runs the analyze walk over the captured
// statement list. No-op when --borrowck is off. `lex` gives the
// source filename; `syms` gives the function's parameter names.
@ borrowck_fn_end i lex i syms s fname → v {
    ? == g_borrowck 0 {} {
        ( nurl_sym_def g_bck `file` ( nurl_lex_filename lex ) )
        ( bck_analyze ( nurl_sym_get syms `__fn_param_names__` ) )
    }
}

// ── Borrow checker — escape analysis (BORROW.md Phase 3) ───────────
//
// Phase 3 replaces the old five-shape `__captures_byref` name+flag
// closure-escape check with a sound *region* check. A region is a
// scope frame; `g_bck_depth` (the borrowck block-nesting counter,
// maintained by bck_block_enter / bck_block_exit) names it — the
// function body is depth 1, every `?` / `~` / `??` / `{ }` block one
// deeper. An outer (shallower) region outlives every inner one; the
// caller outlives the whole function (conceptually depth 0).
//
// A value is a *stack reference* when it carries a pointer into some
// binding's stack slot. Today the only such values are closures that
// capture a `: ~`-mutable multi-field struct by pointer (the
// `__is_capture_byref` shape) — and, transitively, any closure /
// struct / copy that holds one. A stack reference is tagged with the
// **referent depth**: the deepest (largest) block depth among the
// bindings it points into. The reference must not outlive that depth.
//
// Escape analysis is deliberately *flow-insensitive* and runs at
// parse time: a reference is always created before it can flow
// anywhere, and a reference that can reach an escaping sink on ANY
// path is a bug, so the Phase 0 CFG / lattice buys nothing here.
// Each binding gets two side-table entries (scoped in `syms`, so they
// vanish with the binding — no leak across sibling blocks, the bug
// the old global-ish `__captures_byref` flag had):
//
//   <name>__bdepth    — the block depth the binding was declared at
//   <name>__refdepth  — present iff the binding holds a stack
//                       reference; its value is the referent depth
//
// and one transient side-channel, `__last_expr_refdepth__`, that a
// producer (closure literal / aggregate literal) sets to advertise
// "the expression just evaluated is a stack reference of depth N".
// Consumers reset it before `gen_expr` and read it after, exactly
// like `__last_ident_name__`. The whole pass is inert when
// --borrowck is off (g_bck_depth stays 0, every entry point below
// is a no-op), so emitted IR is byte-identical and the bootstrap
// fixed point is unaffected.
//
// Known boundary (documented, not a bug): `*T` raw pointers stay
// unchecked (BORROW.md watch #5 — `*T` is NURL's `unsafe` FFI ABI),
// and a reference passed *through a helper function* needs an
// interprocedural summary (Phase 7) — a per-function pass cannot see
// whether the callee retains it.

// Referent depth of the expression just evaluated by gen_expr: the
// transient `__last_expr_refdepth__` (set by a closure / aggregate
// literal), else — when the expression was a bare identifier — that
// binding's `<name>__refdepth`. 0 means "not a stack reference"
// (a real referent depth is always >= 1, the function body).
@ bck_expr_refdepth i syms s ident → i {
    ? == g_borrowck 0 { ^ 0 } {}
    : s d ( nurl_sym_get syms `__last_expr_refdepth__` )
    ? != 0 ( nurl_str_len d ) { ^ ( nurl_str_to_int d ) } {}
    ? != 0 ( nurl_str_len ident ) {
        : s rd ( nurl_sym_get syms ( nurl_str_cat ident `__refdepth` ) )
        ? != 0 ( nurl_str_len rd ) { ^ ( nurl_str_to_int rd ) } {}
    } {}
    0
}

// Emit one escape `warning:` as `file:line: warning: <msg>`. The
// check fires parse-time but away from the offending token (after
// `gen_expr` has consumed the whole sub-expression), so — like the
// Phase 1/2 `bck_diag` — it carries the source line explicitly and
// omits the caret rather than pointing at the wrong token.
@ bck_esc_warn i lex i line s msg → v {
    : s loc ( nurl_str_cat3 ( nurl_lex_filename lex ) `:`
        ( nurl_str_int line ) )
    ( nurl_eprintln ( nurl_str_cat3 loc `: warning: ` msg ) )
}

// Record a freshly-declared binding's region (its block depth) and,
// when its initialiser was a stack reference, its referent depth.
// Called from gen_let_or_struct for every `:` binding.
@ bck_esc_let i syms s name i refdepth → v {
    ? == g_borrowck 0 {} {
        ( nurl_sym_def syms ( nurl_str_cat name `__bdepth` )
            ( nurl_str_int g_bck_depth ) )
        ( nurl_sym_def syms ( nurl_str_cat name `__refdepth` )
            ? > refdepth 0 ( nurl_str_int refdepth ) `` )
    }
}

// Re-target an existing binding via `=`. The binding inherits (or
// loses) stack-reference-ness from the RHS; if it now references a
// region deeper than its own declaration the reference outlives the
// referent — an escape.
@ bck_esc_assign i lex i syms i line s name i refdepth → v {
    ? == g_borrowck 0 {} {
        ( nurl_sym_def syms ( nurl_str_cat name `__refdepth` )
            ? > refdepth 0 ( nurl_str_int refdepth ) `` )
        ? > refdepth 0 {
            : s bd ( nurl_sym_get syms ( nurl_str_cat name `__bdepth` ) )
            : i bdv ? == 0 ( nurl_str_len bd ) 1 ( nurl_str_to_int bd )
            ? < bdv refdepth
            { ( bck_esc_warn lex line ( nurl_str_cat3
                `assigning to '` name
                `' a value that references a more deeply scoped binding by pointer - it dangles once that inner scope exits (see docs/GOTCHAS.md item 8)` ) ) }
            {}
        } {}
    }
}

// A stack reference reaching `^`-return or an ownership-taking helper
// escapes the current frame unconditionally (the caller / a heap
// container / a worker thread all outlive every in-function region).
@ bck_esc_check_return i lex i syms i line s ident → v {
    ? & != g_borrowck 0 > ( bck_expr_refdepth syms ident ) 0
    { ( bck_esc_warn lex line `returning a value that references a stack binding by pointer - it dangles after this function returns (move the captured data to a heap-backed handle; see docs/GOTCHAS.md item 5)` ) }
    {}
}

@ bck_esc_check_call_arg i lex i syms i line s ident s fname → v {
    ? & != g_borrowck 0 > ( bck_expr_refdepth syms ident ) 0
    { ( bck_esc_warn lex line ( nurl_str_cat3
        `passing a value that references a stack binding by pointer to '` fname
        `' - it escapes the current stack frame and dangles (move it to a heap-backed handle; see docs/GOTCHAS.md item 8)` ) ) }
    {}
}

// ── Statement ──────────────────────────────────────────────────────

@ gen_stmt i lex i syms i cg → s {
    // DWARF Phase 4: snapshot the source line/col of this statement's
    // first token and seed a fresh DILocation. emit_dbg_eol attaches
    // it to every call/ret/br emitted by the dispatched gen_* below,
    // so gdb's `step` / `next` advance one NURL source line at a time
    // and `break foo.nu:N` resolves to the right block.
    ? & != g_dbg_enabled 0 != g_dbg_current_subprogram 0
    { = g_dbg_current_loc ( dbg_emit_location
        ( nurl_lex_line lex ) ( nurl_lex_col lex )
        g_dbg_current_subprogram ) }
    {}
    : i tt ( nurl_lex_type lex )
    : i bck_line ( nurl_lex_line lex )
    // Record this statement's start line for gen_ident's cascade-aware
    // "unexpected token" diagnostic (see g_stmt_line).
    = g_stmt_line bck_line
    : s gs_rv ? == tt TT_COLON ( gen_let_or_struct lex syms cg )
    ? == tt TT_EQ ( gen_assign lex syms cg )
    ? == tt TT_TILDE ( gen_loop lex syms cg )
    ? == tt TT_SEMICOL ( gen_defer lex syms cg )
    {  // Bare expression in statement position. Record a `call`-shaped
       // statement only for a parenthesised call `( fn ... )`; `?` / `??`
       // control flow is captured by the gen_block_ret depth markers
       // instead, so it is not double-recorded here.
        : s bck_ev ( gen_expr lex syms cg )
        ? == tt TT_LPAREN { ( bck_record `expr` `` bck_line ) } {}
        bck_ev
    }
    // Borrow checker (Phase 1): drain this statement's move stash into
    // `move` rows — placed AFTER the statement's own record so the
    // consuming call itself reads the binding while still Owned.
    ( bck_flush_moves )
    gs_rv
}

// Soft check for the docs/GOTCHAS.md §3 pattern: a `:` binding declares
// a name that already names a parameter of the enclosing function (or
// closure). The classic foot-gun is `: i z + z 719468` where `z` is a
// parameter; the new `z` shadows the parameter from this line forward
// and any later read silently rebinds to the new value.
//
// Scope is the nearest @-decl OR closure body — `__fn_param_names__`
// is reset to the closure's own param list inside gen_closure_expr via
// nurl_sym_push, so a `:` inside a closure body checks against the
// closure's params (which is the correct lexical scope).
//
// We deliberately do NOT warn on shadowing of a `:` binding from an
// outer block — local-by-local shadowing is sometimes intentional
// (loop accumulators, two unrelated locals with the same generic
// name like `n` or `i`). Parameter shadowing is almost always a bug.
@ __warn_if_shadows_param i lex i syms s name → v {
    : s param_names ( nurl_sym_get syms `__fn_param_names__` )
    ? & != 0 ( nurl_str_len param_names ) ( str_contains_word param_names name )
    { ( warn lex ( nurl_str_cat3 `'` name `' shadows the enclosing function's parameter - rename (see docs/GOTCHAS.md item 3)` ) ) }
    {}
}

@ gen_let_or_struct i lex i syms i cg → s {
    // Borrow checker: source line of the `:` token, for the record.
    : i bck_line ( nurl_lex_line lex )
    ( nurl_lex_advance lex )
    // Check for optional ~ (mutable) token
    : b had_mutability_check | == ( nurl_lex_type lex ) TT_TILDE ( is_type_start ( nurl_lex_type lex ) )
    : b is_mutable == ( nurl_lex_type lex ) TT_TILDE
    ? is_mutable { ( nurl_lex_advance lex ) } {}
    // GOTCHAS.md item 6: `: ~ * T name init` (mutable pointer to T)
    // miscompiles in long-running write loops — confirmed via the CSV
    // P2c hoist attempt where writes started segfaulting at ~row 66k.
    // Warn (don't `die`) because trivial isolated cases work and the
    // warning is advisory; suggest the immutable `: *T` alternative
    // or re-fetching the pointer per iteration.
    ? & is_mutable == ( nurl_lex_type lex ) TT_STAR
    { ( warn lex `mutable pointer binding ': ~ *T' miscompiles in long-running write loops (deterministic crash ~tens-of-thousands of iterations). Prefer immutable ': *T' + re-fetch on grow, or carry the address as an i64 and cast per use. See docs/GOTCHAS.md item 10.` ) }
    {}
    // Check if first token could be a type name by looking it up in symbol table
    ? & == ( nurl_lex_type lex ) TT_IDENT == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_lex_val lex ) ) )
    {  // Type inference: plain IDENT that's not a known type
        : s name ( nurl_lex_val lex )
        ( __warn_if_shadows_param lex syms name )
        ( nurl_lex_advance lex )
        : b rhs_is_slice_lit == ( nurl_lex_type lex ) TT_LBRACK
        // Borrow checker (Phase 2): snapshot the RHS's first token —
        // a bare identifier RHS is a binding-to-binding alias copy.
        : i bck_rhs_tt ( nurl_lex_type lex )
        : s bck_rhs_val ( nurl_lex_val lex )
        ( nurl_sym_def syms `__last_call_ret_owned__` `` )
        ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
        ( nurl_sym_def syms `__last_expr_refdepth__` `` )
        : s val ( gen_expr lex syms cg )
        : s vt ( nurl_get_last_type )
        // Borrow checker: record this binding (inference path).
        ( bck_record `let` name bck_line )
        ( bck_let_alias syms is_mutable bck_rhs_tt bck_rhs_val vt bck_line )
        : b rhs_is_owned_call != 0 ( nurl_str_len ( nurl_sym_get syms `__last_call_ret_owned__` ) )
        // Escape analysis (BORROW.md Phase 3): stamp this binding's
        // region (block depth) and, when the initialiser was a stack
        // reference — a closure literal capturing a binding by
        // pointer, an aggregate holding one, or a copy of such a
        // binding — its referent depth, so gen_ret / gen_assign /
        // gen_call reject escapes (docs/GOTCHAS.md item 8).
        ( bck_esc_let syms name ( bck_expr_refdepth syms
            ? ( is_ident_tok bck_rhs_tt ) bck_rhs_val `` ) )
        : s ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ptr )
        ( nurl_print ` = alloca ` ) ( nurl_print vt ) ( nurl_print `\n` )
        ( nurl_print `  store ` ) ( nurl_print vt ) ( nurl_print ` ` )
        ( nurl_print val ) ( nurl_print `, ` ) ( nurl_print vt )
        ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
        ( dbg_declare_local name ptr vt ( nurl_lex_line lex ) 0 syms )
        ( nurl_sym_def syms name vt )
        ( nurl_sym_def syms ( nurl_str_cat name `__ptr` ) ptr )
        // Only mark mutability if explicitly specified with ~
        ? is_mutable
        { ( nurl_sym_def syms ( nurl_str_cat name `__mutable` ) `1` ) }
        {}
        ? | rhs_is_slice_lit & rhs_is_owned_call ( mem_is_slice_ty vt )
        { ( mem_own_add syms name ) }
        {}
        // Phase 2B: string ownership tracking (opt-in)
        ? != 0 g_auto_drop_strings
        { ? & ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` ) ( seq vt `i8*` )
            { ( mem_own_add_str syms ptr ) }
            {}
        }
        {}
        // Phase 2C: struct-field ownership — if RHS was `@ T { ... }` and one
        // or more fields came from a fresh allocating i8* call, register a
        // drop for each such field tied to this binding's alloca.
        ? != 0 g_auto_drop_strings
        { ( mem_register_agg_owned_fields syms ptr vt ) }
        {}
        // Phase 2D: User Drop trait
        ? != 0 g_auto_drop_strings
        { : s impl_key ( nurl_str_cat `drop##` vt )
            : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
            ? != 0 ( nurl_str_len impl_mangle_key )
            { ( mem_own_add_user_drop syms ptr vt ) }
            {}
        }
        {}
        // Mark as having new syntax only if mutability was checked
        // TEMPORARILY DISABLED: ? had_mutability_check
        //   { ( nurl_sym_def syms ( nurl_str_cat name `__newsyntax` ) `1` ) }
        //   {}
        ^ val
    }
    // Explicit type annotation.
    { ( nurl_sym_def g_res_type_syms `__last_res_nurl__` `` )
        ( nurl_sym_def g_res_type_syms `__last_nurl_type__` `` )
        : s ptype ( parse_type lex )
        // Capture the NURL form of `! T E` when present, so gen_match can
        // recover the inner T (e.g. `Json`) for struct-handle reconstruction.
        // parse_type's recursive descent through parse_type_res leaves the
        // outermost `! T E` form here; nested ones get overwritten but only
        // the outer one matters at this binding.
        : s let_res_nurl ( nurl_sym_get g_res_type_syms `__last_res_nurl__` )
        : s let_nurl_type ( nurl_sym_get g_res_type_syms `__last_nurl_type__` )
        ? ( is_ident_tok ( nurl_lex_type lex ) )
        { : s name ( nurl_lex_val lex )
            ( __warn_if_shadows_param lex syms name )
            ( nurl_lex_advance lex )
            // Tag the binding with its NURL source type + signedness
            // (consulted at gen_cast / coerce_store_val sites). Empty
            // when ptype came from a non-base type (pointer / slice /
            // closure / aggregate) — signedness only meaningfully
            // applies to integer-and-float bases.
            ? != 0 ( nurl_str_len let_nurl_type )
            { ( nurl_sym_def syms ( nurl_str_cat name `__nurl_type` ) let_nurl_type )
                ? ( nurl_type_is_unsigned let_nurl_type )
                { ( nurl_sym_def syms ( nurl_str_cat name `__unsigned` ) `1` ) }
                {} }
            {}
            // Stash inner-T and inner-E NURL idents under
            // `<name>__res_nurl_T` / `<name>__res_nurl_E` for later retrieval
            // by gen_match's payload-binding logic. T is used for the Ok arm
            // (pattern `T`) and E for the Err arm (pattern `F`) when the
            // arm needs struct-handle reconstruction from the i64 payload.
            ? != 0 ( nurl_str_len let_res_nurl )
            { : s inner_t ( str_first_word ( str_skip_word let_res_nurl ) )
                : s inner_e ( str_first_word ( str_skip_word ( str_skip_word let_res_nurl ) ) )
                ( nurl_sym_def syms ( nurl_str_cat name `__res_nurl_T` ) inner_t )
                ( nurl_sym_def syms ( nurl_str_cat name `__res_nurl_E` ) inner_e ) }
            {}
            // ALSO stash the LLVM form of T so gen_match can reconstruct
            // single-pointer-handle structs (Vec/String/Channel/Thread)
            // whose NURL source is a parenthesised compound like
            // `( Vec u )` — `inner_t` above is just `(` in that case
            // and won't look up to anything useful.
            : s let_res_t_llvm ( nurl_sym_get g_res_type_syms `__last_res_t_llvm__` )
            ? != 0 ( nurl_str_len let_res_t_llvm )
            { ( nurl_sym_def syms ( nurl_str_cat name `__res_t_llvm` ) let_res_t_llvm ) }
            {}
            // Mirror for `? T`: stash inner-T's NURL token + LLVM type
            // so gen_match's T-arm payload binding can propagate the
            // unsigned flag to the alloca for `?u` / `?u16` / `?u32` /
            // `?u64` matches. Without this the alloca drops the flag
            // and a downstream `# i b` cast sign-extends high-bit-set
            // bytes (bit us in bytes_to_hex over SHA-1 digests).
            : s let_opt_nurl_t ( nurl_sym_get g_res_type_syms `__last_opt_nurl_t__` )
            ? != 0 ( nurl_str_len let_opt_nurl_t )
            { ( nurl_sym_def syms ( nurl_str_cat name `__opt_nurl_T` ) let_opt_nurl_t )
                ( nurl_sym_def g_res_type_syms `__last_opt_nurl_t__` `` ) }
            {}
            ? == ( nurl_lex_type lex ) TT_LBRACE
            { ( nurl_lex_advance lex )
                ~ != ( nurl_lex_type lex ) TT_RBRACE { ( nurl_lex_advance lex ) }
                ( nurl_lex_advance lex )
                // Escape analysis: a `{ }` zero-init binding is never a
                // stack reference, but still record its region so a
                // later `=` of a reference into it compares depths
                // correctly.
                ( bck_esc_let syms name 0 )
                ^ `undef`
            }
            { : b rhs_is_slice_lit == ( nurl_lex_type lex ) TT_LBRACK
                // Borrow checker (Phase 2): snapshot the RHS's first
                // token — a bare-identifier RHS is an alias copy.
                : i bck_rhs_tt ( nurl_lex_type lex )
                : s bck_rhs_val ( nurl_lex_val lex )
                ( nurl_sym_def syms `__last_call_ret_owned__` `` )
                ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
                ( nurl_sym_def syms `__last_expr_refdepth__` `` )
                : s val ( gen_expr lex syms cg )
                : s vt ( nurl_get_last_type )
                // Borrow checker: record this binding (typed path).
                ( bck_record `let` name bck_line )
                ( bck_let_alias syms is_mutable bck_rhs_tt bck_rhs_val vt bck_line )
                : b rhs_is_owned_call != 0 ( nurl_str_len ( nurl_sym_get syms `__last_call_ret_owned__` ) )
                // Escape analysis (BORROW.md Phase 3): stamp region +
                // referent depth — see the type-inference path above.
                ( bck_esc_let syms name ( bck_expr_refdepth syms
                    ? ( is_ident_tok bck_rhs_tt ) bck_rhs_val `` ) )

                // Debug: show types being converted
                ( nurl_print `  ; DEBUG: val=` ) ( nurl_print val ) ( nurl_print ` vt=` ) ( nurl_print vt ) ( nurl_print ` ptype=` ) ( nurl_print ptype ) ( nurl_print `\n` )

                // Widen i1 short-circuit / comparison results to the declared
                // integer width before storing (`: i can_l & …` etc.).
                : s widened_val ( coerce_store_val val vt ptype syms cg )
                // Handle closure to function pointer conversion
                : s store_val ( convert_closure_arg widened_val vt ptype cg )

                : s ptr ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print ptr )
                ( nurl_print ` = alloca ` ) ( nurl_print ptype ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print ptype ) ( nurl_print ` ` )
                ( nurl_print store_val ) ( nurl_print `, ` ) ( nurl_print ptype )
                ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                ( dbg_declare_local name ptr ptype ( nurl_lex_line lex ) 0 syms )
                ( nurl_sym_def syms name ptype )
                ( nurl_sym_def syms ( nurl_str_cat name `__ptr` ) ptr )
                // Only mark mutability if explicitly specified with ~
                ? is_mutable
                { ( nurl_sym_def syms ( nurl_str_cat name `__mutable` ) `1` ) }
                {}
                ? | rhs_is_slice_lit & rhs_is_owned_call ( mem_is_slice_ty ptype )
                { ( mem_own_add syms name ) }
                {}
                // Phase 2B: string ownership tracking (opt-in)
                ? != 0 g_auto_drop_strings
                { ? & ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` ) ( seq ptype `i8*` )
                    { ( mem_own_add_str syms ptr ) }
                    {}
                }
                {}
                // Phase 2C: struct-field ownership (see type-inference path).
                ? != 0 g_auto_drop_strings
                { ( mem_register_agg_owned_fields syms ptr ptype ) }
                {}
                // Phase 2D: User Drop trait
                ? != 0 g_auto_drop_strings
                { : s impl_key ( nurl_str_cat `drop##` ptype )
                    : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
                    ? != 0 ( nurl_str_len impl_mangle_key )
                    { ( mem_own_add_user_drop syms ptr ptype ) }
                    {}
                }
                {}
                // Mark as having new syntax only if mutability was checked
                // TEMPORARILY DISABLED: ? had_mutability_check
                //   { ( nurl_sym_def syms ( nurl_str_cat name `__newsyntax` ) `1` ) }
                //   {}
                ^ val
            }
        }
        { ( die lex `expected variable name in let` ) }
    }
}

@ gen_assign i lex i syms i cg → s {
    // Borrow checker: source line of the `=` token.
    : i bck_line ( nurl_lex_line lex )
    ( nurl_lex_advance lex )
    // Field store: = . obj field val
    ? == ( nurl_lex_type lex ) TT_DOT
    { ^ ( gen_field_store lex syms cg ) }
    {}
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s name ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        // Check mutability before allowing assignment
        : s mut_check ( nurl_sym_get syms ( nurl_str_cat name `__mutable` ) )
        : s vt ( nurl_sym_get syms name )
        : s ptr ( nurl_sym_get syms ( nurl_str_cat name `__ptr` ) )
        : s glb ( nurl_sym_get syms ( nurl_str_cat name `__global` ) )
        : s param_check ( nurl_sym_get syms ( nurl_str_cat name `__param` ) )
        // Check mutability only for variables using new syntax
        : s newsyntax_check ( nurl_sym_get syms ( nurl_str_cat name `__newsyntax` ) )
        ? != 0 ( nurl_str_len newsyntax_check )
        {  // Variable uses new syntax, check if it's mutable
            ? == 0 ( nurl_str_len mut_check )
            {  // Variable exists with new syntax but is immutable
                ? != 0 ( nurl_str_len param_check )
                { ( die lex ( nurl_str_cat `cannot assign to immutable parameter: ` name ) ) }
                { ? != 0 ( nurl_str_len glb )
                    { ( die lex ( nurl_str_cat `cannot assign to immutable global: ` name ) ) }
                    { ( die lex ( nurl_str_cat `cannot assign to immutable variable: ` name ) ) }
                }
            }
            {}
        }
        {}
        // Always check parameters regardless of syntax
        ? & == 0 ( nurl_str_len mut_check ) != 0 ( nurl_str_len param_check )
        { ( die lex ( nurl_str_cat `cannot assign to immutable parameter: ` name ) ) }
        {}
        // Phase 2B reassignment-drop: if the LHS is an owned i8* binding and
        // the RHS is a fresh allocating call, free the old value before
        // overwriting. We gate on RHS being a fresh owned-call (not an alias
        // load) to avoid double-free / use-after-free when the user writes
        // `= x y` where y aliases x's heap.
        : b lhs_is_owned_str & & != 0 g_auto_drop_strings
        ( seq vt `i8*` )
        ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) ptr )
        ? lhs_is_owned_str { ( nurl_sym_def syms `__last_call_ret_owned__` `` ) } {}
        // Escape analysis (BORROW.md Phase 3): snapshot the RHS's
        // first token (a bare identifier may copy a stack reference)
        // and clear the side-channel a closure / aggregate literal
        // RHS would publish.
        : i bck_rhs_tt ( nurl_lex_type lex )
        : s bck_rhs_val ( nurl_lex_val lex )
        ( nurl_sym_def syms `__last_expr_refdepth__` `` )
        : s val ( gen_expr lex syms cg )
        // Borrow checker: record this assignment.
        ( bck_record `assign` name bck_line )
        // Escape analysis: re-target `name`. If the RHS is a stack
        // reference into a region deeper than `name`'s own, the
        // reference outlives its referent — an escape.
        ( bck_esc_assign lex syms bck_line name ( bck_expr_refdepth syms
            ? ( is_ident_tok bck_rhs_tt ) bck_rhs_val `` ) )
        : b rhs_is_owned_call & lhs_is_owned_str
        ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` )
        ? rhs_is_owned_call
        { : s old_reg ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print old_reg )
            ( nurl_print ` = load i8*, i8** ` ) ( nurl_print ptr ) ( nurl_print `\n` )
            ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print old_reg ) ( nurl_print `)` ) ( emit_dbg_eol )
        }
        {}
        // Widen i1 short-circuit / comparison results to the LHS's
        // declared integer width, so `= myi64 & a b` stores cleanly.
        : s rhs_ty ( nurl_get_last_type )
        : s store_val ( coerce_store_val val rhs_ty vt syms cg )
        ? != 0 ( nurl_str_len ptr )
        { ( nurl_print `  store ` ) ( nurl_print vt ) ( nurl_print ` ` )
            ( nurl_print store_val ) ( nurl_print `, ` ) ( nurl_print vt )
            ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
        }
        { ? != 0 ( nurl_str_len glb )
            { ( nurl_print `  store ` ) ( nurl_print vt ) ( nurl_print ` ` )
                ( nurl_print store_val ) ( nurl_print `, ` ) ( nurl_print vt )
                ( nurl_print `* @` ) ( nurl_print name ) ( nurl_print `\n` )
            }
            {}
        }
        // Publish the LHS type as the assignment's result type. If the
        // assignment lands as the last expression of a match arm or block
        // ( `?? r { F e → { = err e } }` ), gen_match's phi-typing logic
        // queries nurl_get_last_type to decide arm_type — without this it
        // would see whatever coerce_store_val's RHS-evaluation last set,
        // which can be the un-coerced value type (e.g. raw i64 for the
        // RHS expression) and disagree with the stored register's actual
        // type (`%WsErr` post-coercion), producing a phi type mismatch.
        ( nurl_set_last_type vt )
        ^ store_val
    }
    { ( die lex `expected name after =` ) }
}

// ── Field store = . ptr field val ─────────────────────────────────────
// Emits GEP + store for = . ptr_expr field_name rhs_expr.
// Called after gen_assign has already consumed '='.
// Precondition: current token is TT_DOT.

@ gen_field_store i lex i syms i cg → s {
    ( nurl_lex_advance lex )  // consume '.'
    // Save object name before gen_expr consumes the token (needed for struct-by-value alloca lookup)
    : s obj_name ? ( is_ident_tok ( nurl_lex_type lex ) ) ( nurl_lex_val lex ) ``
    : s pv ( gen_expr lex syms cg )  // pointer/aggregate value
    : s pt ( nurl_get_last_type )  // LLVM type, e.g. "%Node*", "i64*", "{ T*, i64 }", or "%Pair"

    // Slice aggregate "{ T*, i64 }": extract data ptr, then GEP + store
    ? == ( nurl_str_get pt 0 ) 123
    { : i ptlen ( nurl_str_len pt )
        : s ptr_ty ( nurl_str_slice pt 2 - - ptlen 7 2 )
        : s elem_ty ( nurl_str_slice ptr_ty 0 - ( nurl_str_len ptr_ty ) 1 )
        : s data_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print data_ptr )
        ( nurl_print ` = extractvalue ` ) ( nurl_print pt )
        ( nurl_print ` ` ) ( nurl_print pv ) ( nurl_print `, 0\n` )
        ? == ( nurl_lex_type lex ) TT_INT
        { : i idx ( nurl_lex_inum lex )
            ( nurl_lex_advance lex )
            : s rhs ( gen_expr lex syms cg )
            : s gep ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print gep )
            ( nurl_print ` = getelementptr ` ) ( nurl_print elem_ty )
            ( nurl_print `, ` ) ( nurl_print ptr_ty )
            ( nurl_print ` ` ) ( nurl_print data_ptr )
            ( nurl_print `, i32 ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
            ( nurl_print `  store ` ) ( nurl_print elem_ty )
            ( nurl_print ` ` ) ( nurl_print rhs )
            ( nurl_print `, ` ) ( nurl_print elem_ty )
            ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
            ^ rhs
        }
        { : s idx_val ( gen_expr lex syms cg )
            : s idx_type ( nurl_get_last_type )
            : s rhs ( gen_expr lex syms cg )
            : s gep ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print gep )
            ( nurl_print ` = getelementptr ` ) ( nurl_print elem_ty )
            ( nurl_print `, ` ) ( nurl_print ptr_ty )
            ( nurl_print ` ` ) ( nurl_print data_ptr )
            ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
            ( nurl_print `  store ` ) ( nurl_print elem_ty )
            ( nurl_print ` ` ) ( nurl_print rhs )
            ( nurl_print `, ` ) ( nurl_print elem_ty )
            ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
            ^ rhs
        }
    }
    // Not a slice: check if this is numeric indexing or field name
    { ? == ( nurl_lex_type lex ) TT_INT
        {  // Numeric index: array access like raw_ptr[0] = value
            : i idx ( nurl_lex_inum lex )
            ( nurl_lex_advance lex )
            // Generate RHS
            : s rhs ( gen_expr lex syms cg )
            // Strip trailing '*' to get the element type, e.g. "i64*" → "i64"
            : i ptlen ( nurl_str_len pt )
            : s elem_type ( nurl_str_slice pt 0 - ptlen 1 )
            // Emit array indexing GEP + store
            : s gep ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print gep )
            ( nurl_print ` = getelementptr ` ) ( nurl_print elem_type )
            ( nurl_print `, ` ) ( nurl_print pt )
            ( nurl_print ` ` ) ( nurl_print pv )
            ( nurl_print `, i32 ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
            ( nurl_print `  store ` ) ( nurl_print elem_type )
            ( nurl_print ` ` ) ( nurl_print rhs )
            ( nurl_print `, ` ) ( nurl_print elem_type )
            ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
            ^ rhs
        }
        {  // Not TT_INT: struct field name or raw-pointer variable index
            : i ptlen ( nurl_str_len pt )
            : b pt_is_ptr == ( nurl_str_get pt - ptlen 1 ) 42
            ? pt_is_ptr
            {  // pt ends with '*': pointer to struct OR raw pointer
                : s st ( nurl_str_slice pt 0 - ptlen 1 )
                ? == ( nurl_str_get st 0 ) 37
                {  // Struct pointer "%T*": next token is either a field
                    // name or a variable used as array index (e.g.
                    // `= . data idx x` where data: *Match, idx is the
                    // index var). When an IDENT is BOTH a local int var
                    // AND a struct field name, the array-store path is
                    // the default — this matches how `stdlib/core/vec.nu`
                    // writes elements with index vars whose names (`len`,
                    // `idx`, `i`) happen to coincide with struct fields.
                    //
                    // EXCEPTION: when the IDENT is a function PARAMETER
                    // that shadows a field of the same name, the user
                    // almost certainly meant the field — the "store the
                    // `cap` argument into `impl.cap`" pattern in
                    // `stdlib/std/arena.nu` is the canonical case. Pre-
                    // 2026-05-17 the param branch silently took the
                    // array-store path and emitted `getelementptr %S, %S*
                    // %impl, i64 %cap` (value-as-index, no field offset).
                    // Closes docs/GOTCHAS.md item 10.
                    : i stlen ( nurl_str_len st )
                    : s sname ( nurl_str_slice st 1 - stlen 1 )
                    : s fname ( nurl_lex_val lex )
                    : s fidx_s ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
                    : b is_field_ident ( is_ident_tok ( nurl_lex_type lex ) )
                    : b is_field_match & is_field_ident != 0 ( nurl_str_len fidx_s )
                    : s is_param ( nurl_sym_get syms ( nurl_str_cat fname `__param` ) )
                    : b field_wins & is_field_match != 0 ( nurl_str_len is_param )
                    : s var_t ( nurl_sym_get syms fname )
                    ? & ! field_wins > ( int_width var_t ) 0
                    {  // IDENT is an integer variable (and not a param
                        // shadowing a field) — array-style store *T[idx] = rhs.
                        : s idx_val ( gen_expr lex syms cg )
                        : s idx_type ( nurl_get_last_type )
                        : s rhs ( gen_expr lex syms cg )
                        : s gep ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print gep )
                        ( nurl_print ` = getelementptr ` ) ( nurl_print st )
                        ( nurl_print `, ` ) ( nurl_print pt )
                        ( nurl_print ` ` ) ( nurl_print pv )
                        ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                        ( nurl_print `  store ` ) ( nurl_print st )
                        ( nurl_print ` ` ) ( nurl_print rhs )
                        ( nurl_print `, ` ) ( nurl_print st )
                        ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                        ^ rhs
                    }
                    {  // Not an integer variable (or shadowed by a field): try field.
                        ? != 0 ( nurl_str_len fidx_s )
                        {  // IDENT is a field name: struct field access
                            ( nurl_lex_advance lex )
                            : s ftype ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
                            : i fidx ( nurl_str_to_int fidx_s )
                            : s rhs ( gen_expr lex syms cg )
                            : s gep ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print gep )
                            ( nurl_print ` = getelementptr ` ) ( nurl_print st )
                            ( nurl_print `, ` ) ( nurl_print pt )
                            ( nurl_print ` ` ) ( nurl_print pv )
                            ( nurl_print `, i32 0, i32 ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
                            ( nurl_print `  store ` ) ( nurl_print ftype )
                            ( nurl_print ` ` ) ( nurl_print rhs )
                            ( nurl_print `, ` ) ( nurl_print ftype )
                            ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                            ^ rhs
                        }
                        {  // Neither integer variable nor field: check for non-integer variable index (error likely but follow general path)
                            ? != 0 ( nurl_str_len var_t )
                            { : s idx_val ( gen_expr lex syms cg )
                                : s idx_type ( nurl_get_last_type )
                                : s rhs ( gen_expr lex syms cg )
                                : s gep ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print gep )
                                ( nurl_print ` = getelementptr ` ) ( nurl_print st )
                                ( nurl_print `, ` ) ( nurl_print pt )
                                ( nurl_print ` ` ) ( nurl_print pv )
                                ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                                ( nurl_print `  store ` ) ( nurl_print st )
                                ( nurl_print ` ` ) ( nurl_print rhs )
                                ( nurl_print `, ` ) ( nurl_print st )
                                ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                                ^ rhs
                            }
                            { ( die lex ( nurl_str_cat `unknown field or variable: ` fname ) ) }
                        }
                    }
                }
                {  // Raw pointer with variable index: one-index GEP
                    : s idx_val ( gen_expr lex syms cg )
                    : s idx_type ( nurl_get_last_type )
                    : s rhs ( gen_expr lex syms cg )
                    : s gep ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print gep )
                    ( nurl_print ` = getelementptr ` ) ( nurl_print st )
                    ( nurl_print `, ` ) ( nurl_print pt )
                    ( nurl_print ` ` ) ( nurl_print pv )
                    ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                    ( nurl_print `  store ` ) ( nurl_print st )
                    ( nurl_print ` ` ) ( nurl_print rhs )
                    ( nurl_print `, ` ) ( nurl_print st )
                    ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                    ^ rhs
                }
            }
            {  // Struct by value "%T": use alloca ptr from obj_name__ptr as GEP base
                : s alloca_ptr ( nurl_sym_get syms ( nurl_str_cat obj_name `__ptr` ) )
                : s pt_ptr ( nurl_str_cat pt `*` )
                : s sname ( nurl_str_slice pt 1 - ptlen 1 )
                : s fname ( nurl_lex_val lex )
                ( nurl_lex_advance lex )
                : s fidx_s ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
                : s ftype ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
                : i fidx ( nurl_str_to_int fidx_s )
                : s rhs ( gen_expr lex syms cg )
                : s gep ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print gep )
                ( nurl_print ` = getelementptr ` ) ( nurl_print pt )
                ( nurl_print `, ` ) ( nurl_print pt_ptr )
                ( nurl_print ` ` ) ( nurl_print alloca_ptr )
                ( nurl_print `, i32 0, i32 ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print ftype )
                ( nurl_print ` ` ) ( nurl_print rhs )
                ( nurl_print `, ` ) ( nurl_print ftype )
                ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                ^ rhs
            }
        }
    }
}

// ── Cast # type expr ───────────────────────────────────────────────

// int_width: LLVM integer type string → bit width, or 0 if not iN.
@ int_width s ty → i {
    ? ( seq ty `i1` ) 1
    ? ( seq ty `i8` ) 8
    ? ( seq ty `i16` ) 16
    ? ( seq ty `i32` ) 32
    ? ( seq ty `i64` ) 64
    0
}

@ gen_cast i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s dt ( parse_type lex )
    // GOTCHAS.md item 4: `# T { ... }` parses as cast-to-T applied to a
    // block expression, NOT as a struct/enum literal. Users coming
    // from Rust / TypeScript reflexively write `#` here and silently
    // get wrong shapes. Detect the unambiguous pattern (target is a
    // registered struct OR enum, next token is `{`) and stop with a
    // pointing diagnostic.
    ? & == ( nurl_lex_type lex ) TT_LBRACE & > ( nurl_str_len dt ) 1 == ( nurl_str_get dt 0 ) 37
    { : s tname ( nurl_str_slice dt 1 - ( nurl_str_len dt ) 1 )
        : s is_enum ( nurl_sym_get syms ( nurl_str_cat tname `__variants` ) )
        : s is_struct ( nurl_sym_get syms ( nurl_str_cat3 tname `__idx_1` `__type` ) )
        ? | != 0 ( nurl_str_len is_enum ) != 0 ( nurl_str_len is_struct )
        { ( die lex ( nurl_str_cat3
            `'#' is the cast operator; struct/enum literals use '@'. Write '@ `
            tname ` { ... }' instead. See docs/GOTCHAS.md item 9.` ) ) }
        {}
    }
    {}
    : s val ( gen_expr lex syms cg )
    : s st ( nurl_get_last_type )
    : s res ( nurl_cg_reg cg )
    // Detect pointer source/destination (LLVM type ends with '*')
    : i stlen ( nurl_str_len st )
    : i dtlen ( nurl_str_len dt )
    : b src_ptr == ( nurl_str_get st - stlen 1 ) 42
    : b dst_ptr == ( nurl_str_get dt - dtlen 1 ) 42
    // Closure-field-extract:  ( # *u f 0 ) → fn ptr (cast to dst)
    //                          ( # *u f 1 ) → env ptr (cast to dst)
    // Trigger: src type is closure-shape `{ R (i8*…)*, i8* }`, dst is pointer,
    // next lexer token is INT 0 or 1. Used to feed C-runtime callback APIs
    // (thread_spawn et al.) the raw fn/env pair NURL closures decompose into.
    : b is_closure_src & & >= stlen 9
    ( seq ( nurl_str_slice st 0 2 ) `{ ` )
    ( seq ( nurl_str_slice st - stlen 7 7 ) `, i8* }` )
    : b extract_idx_pending & & is_closure_src dst_ptr
    & == ( nurl_lex_type lex ) TT_INT
    | == ( nurl_lex_inum lex ) 0 == ( nurl_lex_inum lex ) 1
    ? extract_idx_pending
    { : i fld ( nurl_lex_inum lex )
        ( nurl_lex_advance lex )  // consume the 0 / 1
        : s elem_ty ? == fld 0 ( nurl_str_slice st 2 - stlen 9 ) `i8*`
        : s ev ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ev )
        ( nurl_print ` = extractvalue ` ) ( nurl_print st )
        ( nurl_print ` ` ) ( nurl_print val )
        ( nurl_print `, ` ) ( nurl_print ( nurl_str_int fld ) ) ( nurl_print `\n` )
        ? ( seq dt elem_ty )
        { ( nurl_set_last_type dt ) ^ ev }
        { ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = bitcast ` ) ( nurl_print elem_ty )
            ( nurl_print ` ` ) ( nurl_print ev )
            ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
            ( nurl_set_last_type dt ) ^ res
        }
    }
    {}
    // Named non-pointer source → integer. Enums and structs both lower
    // to `{ field0, ... }`; `# <int> someAggregate` recovers field 0:
    //   * enum   → field 0 is the i64 variant tag.
    //   * struct → field 0 is the first declared field.
    // The extracted value is normalised to i64 (sext for a narrow int,
    // ptrtoint for a pointer field 0) and then truncated to a narrower
    // dst; a float field 0 goes straight through `fptosi`. A field 0
    // that is itself an aggregate cannot be reduced to an integer.
    : b src_is_named & > stlen 1 == ( nurl_str_get st 0 ) 37
    : i named_dst_iw ( int_width dt )
    ? & & src_is_named > named_dst_iw 0 != ( nurl_str_get st - stlen 1 ) 42
    { : s sname_c ( nurl_str_slice st 1 - stlen 1 )
        : s is_enum_c ( nurl_sym_get syms ( nurl_str_cat sname_c `__variants` ) )
        : s f0t ? != 0 ( nurl_str_len is_enum_c ) `i64`
            ( nurl_sym_get syms ( nurl_str_cat3 sname_c `__idx_0` `__type` ) )
        ? == 0 ( nurl_str_len f0t )
        { ( die lex ( nurl_str_cat3 `cannot cast '` st `' to an integer` ) ) }
        {}
        : s xv ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print xv )
        ( nurl_print ` = extractvalue ` ) ( nurl_print st )
        ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, 0\n` )
        : i f0iw ( int_width f0t )
        : b f0_is_ptr == ( nurl_str_get f0t - ( nurl_str_len f0t ) 1 ) 42
        : b f0_is_fp | ( seq f0t `double` ) ( seq f0t `float` )
        ? f0_is_fp
        { ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = fptosi ` ) ( nurl_print f0t )
            ( nurl_print ` ` ) ( nurl_print xv ) ( nurl_print ` to ` )
            ( nurl_print dt ) ( nurl_print `\n` )
            ( nurl_set_last_type dt ) ^ res }
        {}
        ? & & ! f0_is_fp ! f0_is_ptr == f0iw 0
        { ( die lex ( nurl_str_cat3 `cannot cast '` st `' to an integer: field 0 is an aggregate` ) ) }
        {}
        : s norm ? & ! f0_is_ptr == f0iw 64 xv ( nurl_cg_reg cg )
        ? f0_is_ptr
        { ( nurl_print `  ` ) ( nurl_print norm )
            ( nurl_print ` = ptrtoint ` ) ( nurl_print f0t )
            ( nurl_print ` ` ) ( nurl_print xv ) ( nurl_print ` to i64\n` ) }
        { ? != f0iw 64
            { ( nurl_print `  ` ) ( nurl_print norm )
                ( nurl_print ` = sext ` ) ( nurl_print f0t )
                ( nurl_print ` ` ) ( nurl_print xv ) ( nurl_print ` to i64\n` ) }
            {} }
        ? ( seq dt `i64` )
        { ( nurl_set_last_type dt ) ^ norm }
        { ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = trunc i64 ` ) ( nurl_print norm )
            ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
            ( nurl_set_last_type dt ) ^ res }
    }
    {}
    // Float-side casts. NURL has two float widths: `f` → double, `f32` →
    // float. The cast logic covers four cases involving floats:
    //   * float ↔ double: fpext / fptrunc (shipped 2026-05-14 with f32).
    //   * float-or-double → int: fptosi.
    //   * int → float-or-double: sitofp.
    // Helpers keep the `seq st …` chain readable.
    : b src_is_double ( seq st `double` )
    : b src_is_float ( seq st `float` )
    : b dst_is_double ( seq dt `double` )
    : b dst_is_float ( seq dt `float` )
    : b src_is_fp | src_is_double src_is_float
    : b dst_is_fp | dst_is_double dst_is_float
    ? & src_is_fp dst_is_fp
    {  // float ↔ double conversions.
        ? ( seq st dt )
        { ( nurl_set_last_type dt ) ^ val }
        { ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ? & src_is_float dst_is_double ` = fpext ` ` = fptrunc ` )
            ( nurl_print st ) ( nurl_print ` ` ) ( nurl_print val )
            ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
            ( nurl_set_last_type dt ) ^ res }
    }
    {}
    ? & src_is_fp ! dst_is_fp
    { ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ` = fptosi ` ) ( nurl_print st ) ( nurl_print ` ` )
        ( nurl_print val ) ( nurl_print ` to ` ) ( nurl_print dt )
        ( nurl_print `\n` )
        ( nurl_set_last_type dt )
        ^ res
    }
    ? & ! src_is_fp dst_is_fp
    { ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ` = sitofp ` ) ( nurl_print st )
        ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print ` to ` )
        ( nurl_print dt ) ( nurl_print `\n` )
        ( nurl_set_last_type dt )
        ^ res
    }
    { ? & src_ptr ( seq dt `i64` )
        {  // pointer → i64: ptrtoint
            ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = ptrtoint ` ) ( nurl_print st )
            ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print ` to i64\n` )
            ( nurl_set_last_type `i64` )
            ^ res
        }
        { ? & dst_ptr ( seq st `i64` )
            {  // i64 → pointer: inttoptr
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = inttoptr i64 ` ) ( nurl_print val )
                ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
                ( nurl_set_last_type dt )
                ^ res
            }
            { ? & src_ptr dst_ptr
                {  // pointer → pointer: bitcast
                    ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = bitcast ` ) ( nurl_print st )
                    ( nurl_print ` ` ) ( nurl_print val )
                    ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
                    ( nurl_set_last_type dt )
                    ^ res
                }
                { ? & ( seq st `i64` ) == ( nurl_str_get dt 0 ) 37
                    {  // i64 → struct/enum: reconstruct by inserting val
                        // as field 0. Look up field 0's actual type — three
                        // sub-cases keyed on the shape of f0:
                        //   (a) f0 is a pointer (e.g. %String { s sb }, %Vec):
                        //       inttoptr i64 → ptr, then insertvalue at f0.
                        //   (b) f0 is i64 (e.g. %Pt2 { i64, i64 }, all enums
                        //       whose tag slot is the first field):
                        //       insertvalue undef, i64 val, 0 directly.
                        //   (c) f0 is anything else — a named struct (%String
                        //       inside %Header, %Pt2 inside %Tagged), or a
                        //       primitive like double / i32: packing an
                        //       arbitrary i64 into that slot is not
                        //       meaningful, so emit zeroinitializer. This
                        //       services the standard `@ ? T { F # T 0 }`
                        //       dummy-payload idiom used throughout stdlib
                        //       (vec_get, hashmap, iter combinators) for
                        //       multi-field T whose f0 isn't i64-shaped.
                        //       Closes docs/GOTCHAS.md §4 — vec_get on
                        //       multi-field T no longer miscompiles.
                        : s sname ( nurl_str_slice dt 1 - dtlen 1 )
                        : s f0_ty ( nurl_sym_get syms ( nurl_str_cat3 sname `__idx_0` `__type` ) )
                        : b f0_is_ptr & != 0 ( nurl_str_len f0_ty )
                        == ( nurl_str_get f0_ty - ( nurl_str_len f0_ty ) 1 ) 42
                        : b f0_is_i64 ( seq f0_ty `i64` )
                        // Empty f0_ty: struct not fully registered — fall
                        // through to legacy insertvalue (preserves prior
                        // behaviour for anon / partially-known types).
                        : b f0_unknown == 0 ( nurl_str_len f0_ty )
                        ? f0_is_ptr
                        { : s pv ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print pv )
                            ( nurl_print ` = inttoptr i64 ` ) ( nurl_print val )
                            ( nurl_print ` to ` ) ( nurl_print f0_ty ) ( nurl_print `\n` )
                            ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ` = insertvalue ` ) ( nurl_print dt )
                            ( nurl_print ` undef, ` ) ( nurl_print f0_ty )
                            ( nurl_print ` ` ) ( nurl_print pv ) ( nurl_print `, 0\n` )
                            ( nurl_set_last_type dt )
                            ^ res }
                        { ? | f0_is_i64 f0_unknown
                            { ( nurl_print `  ` ) ( nurl_print res )
                                ( nurl_print ` = insertvalue ` ) ( nurl_print dt )
                                ( nurl_print ` undef, i64 ` ) ( nurl_print val ) ( nurl_print `, 0\n` )
                                ( nurl_set_last_type dt )
                                ^ res }
                            {  // f0 is neither pointer, i64, nor unknown —
                                // produce a zero-initialised whole struct.
                                ( nurl_set_last_type dt )
                                ^ `zeroinitializer` }
                        }
                    }
                    {  // Integer-width conversion (iN → iM).  Three sub-cases:
                        //   * Narrow (sw > dw): trunc.
                        //   * Widen, source unsigned (`__last_unsigned__`
                        //     side-channel set by gen_ident from the
                        //     binding's `__unsigned` flag): zext.
                        //   * Widen, source signed (default): sext.
                        // Equal widths or non-integer types: no-op.
                        : i sw ( int_width st )
                        : i dw ( int_width dt )
                        ? & & > sw 0 > dw 0 != sw dw
                        { : s lu ( nurl_sym_get syms `__last_unsigned__` )
                            : s widen_inst ? != 0 ( nurl_str_len lu ) ` = zext ` ` = sext `
                            ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ? > dw sw widen_inst ` = trunc ` )
                            ( nurl_print st ) ( nurl_print ` ` ) ( nurl_print val )
                            ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
                            ( nurl_set_last_type dt )
                            ^ res
                        }
                        { ( nurl_set_last_type dt ) ^ val }
                    }
                }
            }
        }
    }
}

// ── Member . obj field|index ───────────────────────────────────────

@ gen_member i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s ov ( gen_expr lex syms cg )
    : s ot ( nurl_get_last_type )
    // Snapshot the object pointer's unsigned-ness BEFORE we parse the
    // index (which may itself clobber `__last_unsigned__` via gen_ident).
    // For raw-pointer loads `*X p`, the let-stmt tags the binding with
    // `<name>__unsigned = 1` when X is u/u16/u32/u64 (parse_type_ptr
    // recurses through parse_type_base, which exposes the element NURL
    // type to gen_let_or_struct), and gen_ident copies that flag into
    // `__last_unsigned__` after loading the pointer. We snapshot here
    // and restore after the load so downstream `# i …` casts pick zext
    // — without this, a high-bit-set byte (`0x89`) sign-extends to
    // `0xFFFFFFFFFFFFFF89` and corrupts every subsequent shift+add.
    : s obj_unsigned_snap ( nurl_sym_get syms `__last_unsigned__` )

    // Check object type first to determine access method
    : i otlen ( nurl_str_len ot )
    : b is_ptr == ( nurl_str_get ot - otlen 1 ) 42

    ? is_ptr
    {  // Pointer type. Disambiguate raw pointer (T*) vs struct pointer (%T*):
        //   - INT literal     →  array indexing (works for both)
        //   - IDENT field name on a STRUCT pointer  →  GEP + load by registered field idx
        //   - IDENT variable  →  variable-index array access (raw pointers only)
        ? == ( nurl_lex_type lex ) TT_INT
        {  // Integer literal index
            : i idx ( nurl_lex_inum lex )
            ( nurl_lex_advance lex )
            // Strip trailing '*' to get the element type, e.g. "i64*" → "i64"
            : s elem_type ( nurl_str_slice ot 0 - otlen 1 )
            : s gep ( nurl_cg_reg cg )
            : s res ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print gep )
            ( nurl_print ` = getelementptr ` ) ( nurl_print elem_type )
            ( nurl_print `, ` ) ( nurl_print ot )
            ( nurl_print ` ` ) ( nurl_print ov )
            ( nurl_print `, i32 ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
            ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = load ` ) ( nurl_print elem_type )
            ( nurl_print `, ` ) ( nurl_print elem_type )
            ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
            ( nurl_set_last_type elem_type )
            // Restore unsigned flag from object pointer — for raw-ptr
            // loads, the element shares the pointer's NURL signedness.
            ( nurl_sym_def syms `__last_unsigned__` obj_unsigned_snap )
            ^ res
        }
        { : s elem_type ( nurl_str_slice ot 0 - otlen 1 )
            : b elem_is_struct == ( nurl_str_get elem_type 0 ) 37
            // Struct pointer (%T*): if the IDENT names a struct field,
            // emit `gep %T, %T* ov, i32 0, i32 fidx` + load.
            // Prioritize integer variable index if it exists.
            : b is_field_access F
            : s fname ( nurl_lex_val lex )
            : s var_t ( nurl_sym_get syms fname )
            : s fidx_s ``
            : s ftype ``
            ? & elem_is_struct ( is_ident_tok ( nurl_lex_type lex ) )
            { ? > ( int_width var_t ) 0
                {}  // Integer variable index: skip field access check
                { : s sname ( nurl_str_slice elem_type 1 - ( nurl_str_len elem_type ) 1 )
                    : s fidx_check ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
                    ? != 0 ( nurl_str_len fidx_check )
                    { = is_field_access T
                        = fidx_s fidx_check
                        = ftype ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
                    }
                    {}
                }
            }
            {}
            ? is_field_access
            { ( nurl_lex_advance lex )  // consume field name
                : i fidx ( nurl_str_to_int fidx_s )
                : s gep ( nurl_cg_reg cg )
                : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print gep )
                ( nurl_print ` = getelementptr ` ) ( nurl_print elem_type )
                ( nurl_print `, ` ) ( nurl_print ot )
                ( nurl_print ` ` ) ( nurl_print ov )
                ( nurl_print `, i32 0, i32 ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = load ` ) ( nurl_print ftype )
                ( nurl_print `, ` ) ( nurl_print ftype )
                ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                ( nurl_set_last_type ftype )
                ^ res
            }
            {  // Variable / arbitrary expression index → array-style access
                : s idx_val ( gen_expr lex syms cg )
                : s idx_type ( nurl_get_last_type )
                : s gep ( nurl_cg_reg cg )
                : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print gep )
                ( nurl_print ` = getelementptr ` ) ( nurl_print elem_type )
                ( nurl_print `, ` ) ( nurl_print ot )
                ( nurl_print ` ` ) ( nurl_print ov )
                ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = load ` ) ( nurl_print elem_type )
                ( nurl_print `, ` ) ( nurl_print elem_type )
                ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                ( nurl_set_last_type elem_type )
                // Restore — see obj_unsigned_snap comment above.
                ( nurl_sym_def syms `__last_unsigned__` obj_unsigned_snap )
                ^ res
            }
        }
    }
    {  // Non-pointer type: handle struct field access or aggregate indexing
        ? == ( nurl_lex_type lex ) TT_INT
        {  // Integer literal index for aggregate types
            : i idx ( nurl_lex_inum lex )
            ( nurl_lex_advance lex )
            : b ot_is_opt_res & >= ( nurl_str_len ot ) 6
            ( seq ( nurl_str_slice ot 0 6 ) `{ i1, ` )
            ? & | == ( nurl_str_get ot 0 ) 37 ot_is_opt_res
            == idx 0
            {  // Named struct/enum (%T) or opt/res aggregate ({ i1, T }) at index 0:
                // Return the whole value — consumed by `??` which extractvalues the tag itself.
                // Slices `{ T*, i64 }` are NOT matched here: `. slice 0` must extract
                // the data pointer via the `else` branch below.
                ( nurl_set_last_type ot )
                ^ ov
            }
            {  // Extractvalue for specific field (idx > 0) or primitive types
                : s ft ( compound_field_type ot idx )
                : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ot )
                ( nurl_print ` ` ) ( nurl_print ov )
                ( nurl_print `, ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
                ( nurl_set_last_type ft )
                ^ res
            }
        }
        {  // Named field access for structs or slice types
            ? ( is_ident_tok ( nurl_lex_type lex ) )
            { : s fname ( nurl_lex_val lex )
                ( nurl_lex_advance lex )
                // Slice type check: compound type starts with '{' (ASCII 123)
                // Slice layout: { T*, i64 }  — ptr at index 0, length at index 1
                ? == ( nurl_str_get ot 0 ) 123
                {  // Slice: "ptr" → extractvalue 0, "length" → extractvalue 1,
                    //         anything else → variable element index
                    ? ( seq fname `ptr` )
                    {  // ptr: extractvalue 0, type = T*
                        : s ptr_ty ( nurl_str_slice ot 2 - - ( nurl_str_len ot ) 7 2 )
                        : s res ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print res )
                        ( nurl_print ` = extractvalue ` ) ( nurl_print ot )
                        ( nurl_print ` ` ) ( nurl_print ov ) ( nurl_print `, 0\n` )
                        ( nurl_set_last_type ptr_ty )
                        ^ res
                    }
                    { ? ( seq fname `length` )
                        {  // length: extractvalue 1, type = i64
                            : s res ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ` = extractvalue ` ) ( nurl_print ot )
                            ( nurl_print ` ` ) ( nurl_print ov ) ( nurl_print `, 1\n` )
                            ( nurl_set_last_type `i64` )
                            ^ res
                        }
                        {  // Variable element index: extract data ptr, GEP, load
                            : s ptr_ty ( nurl_str_slice ot 2 - - ( nurl_str_len ot ) 7 2 )
                            : s elem_ty ( nurl_str_slice ptr_ty 0 - ( nurl_str_len ptr_ty ) 1 )
                            // Load the index variable (fname is the variable name)
                            : s idx_lt ( nurl_sym_get syms fname )
                            : s idx_ptr ( nurl_sym_get syms ( nurl_str_cat fname `__ptr` ) )
                            : s idx_val ( load_var cg idx_lt idx_ptr )
                            // Extract data pointer from slice aggregate
                            : s data_ptr ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print data_ptr )
                            ( nurl_print ` = extractvalue ` ) ( nurl_print ot )
                            ( nurl_print ` ` ) ( nurl_print ov ) ( nurl_print `, 0\n` )
                            // GEP + load element
                            : s gep ( nurl_cg_reg cg )
                            : s res ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print gep )
                            ( nurl_print ` = getelementptr ` ) ( nurl_print elem_ty )
                            ( nurl_print `, ` ) ( nurl_print ptr_ty )
                            ( nurl_print ` ` ) ( nurl_print data_ptr )
                            ( nurl_print `, ` ) ( nurl_print idx_lt ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                            ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ` = load ` ) ( nurl_print elem_ty )
                            ( nurl_print `, ` ) ( nurl_print elem_ty )
                            ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                            ( nurl_set_last_type elem_ty )
                            ^ res
                        }
                    }
                }
                {  // Regular struct: use symtable lookup
                    // Strip '%' to get struct name  e.g. "%Node" → "Node"
                    : s sname ( nurl_str_slice ot 1 - otlen 1 )
                    : s fidx_s ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
                    : s ftype ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
                    : i fidx ( nurl_str_to_int fidx_s )
                    : s res ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = extractvalue ` ) ( nurl_print ot )
                    ( nurl_print ` ` ) ( nurl_print ov )
                    ( nurl_print `, ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
                    ( nurl_set_last_type ftype )
                    ^ res
                }
            }
            { ( die lex `expected field name or index after .` ) }
        }
    }
}

// ── Aggregate literal @ T { v0 v1 ... } ───────────────────────────
// Builds a compound type value using a chain of insertvalue instructions.
// Example:  @ ? i { 1 42 }  creates Some(42) as { i1, i64 }.

@ gen_agg_lit i lex i syms i cg → s {
    ( nurl_lex_advance lex )  // consume '@'
    : s agg_ty ( parse_type lex )  // parse the aggregate type
    ( expect lex TT_LBRACE )  // consume '{'
    : s result `undef`
    : i idx 0
    // Phase 2C/2D: collect indices of fields populated by a fresh allocating
    // call (i8* via nurl_str_cat et al, or slice via `[T | ...]` literal /
    // slice-returning call), AND nested owned subfields from inner struct
    // aggregate literals. Exposed via `__last_agg_owned_fields__` as
    // space-separated tokens `<path>:<kind>:<leaf_sname>:<leaf_idx>` — path
    // is dot-separated (flat: single int; nested: e.g. `0.1`). Only applies
    // to named-struct aggregates (agg_ty starting with %).
    : s owned_field_idxs ``
    // Current struct's bare name (without leading %). Empty for anon aggs.
    : s cur_sname ``
    ? == ( nurl_str_get agg_ty 0 ) 37
    { = cur_sname ( nurl_str_slice agg_ty 1 - ( nurl_str_len agg_ty ) 1 ) }
    {}
    // Closure-escape (docs/GOTCHAS.md item 5/8 / BORROW.md Phase 3):
    // track the deepest referent depth among the field values. A field
    // that is a stack reference (a closure capturing a binding by
    // pointer, or a binding / aggregate transitively holding one)
    // makes the WHOLE aggregate a stack reference of that depth, so
    // `gen_let_or_struct` / `gen_ret` reject the escape — otherwise
    // wrapping a byref closure in a struct would silently defeat the
    // `^`-return + escape-call checks.
    : ~ i agg_refdepth 0
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        ? != 0 g_auto_drop_strings
        { ( nurl_sym_def syms `__last_call_ret_owned__` `` )
            ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
        }
        {}
        // Reset the escape + ident-name side-channels so the post-gen_expr
        // check observes only what THIS field expression sets.
        ( nurl_sym_def syms `__last_expr_refdepth__` `` )
        ( nurl_sym_def syms `__last_ident_name__` `` )
        // Snapshot whether this field expr is a slice literal before gen_expr
        // consumes the token. Slice literals don't go through gen_call so
        // `__last_call_ret_owned__` is never set for them.
        : b fld_is_slice_lit == ( nurl_lex_type lex ) TT_LBRACK
        : s fval ( gen_expr lex syms cg )
        : s fty ( nurl_get_last_type )
        // Field is a stack reference if gen_closure_expr / a nested
        // gen_agg_lit just advertised one, or the field named a binding
        // tagged `<name>__refdepth`. Carry up the deepest such depth.
        : i fld_refdepth ( bck_expr_refdepth syms
            ( nurl_sym_get syms `__last_ident_name__` ) )
        ? > fld_refdepth agg_refdepth { = agg_refdepth fld_refdepth } {}
        : s ret_owned ( nurl_sym_get syms `__last_call_ret_owned__` )
        : b is_str_fresh & ( seq fty `i8*` ) ( seq ret_owned `str` )
        : b is_slice_fresh & ( mem_is_slice_ty fty ) | fld_is_slice_lit ( seq ret_owned `1` )
        : s idx_str ( nurl_str_int idx )
        ? & != 0 g_auto_drop_strings is_str_fresh
        { : s tag ( nurl_str_cat3 idx_str `:str:` ( nurl_str_cat3 cur_sname `:` idx_str ) )
            = owned_field_idxs ? == 0 ( nurl_str_len owned_field_idxs )
            tag
            ( nurl_str_cat3 owned_field_idxs ` ` tag )
        }
        {}
        ? & != 0 g_auto_drop_strings is_slice_fresh
        { : s tag ( nurl_str_cat3 idx_str `:slice:` ( nurl_str_cat3 cur_sname `:` idx_str ) )
            = owned_field_idxs ? == 0 ( nurl_str_len owned_field_idxs )
            tag
            ( nurl_str_cat3 owned_field_idxs ` ` tag )
        }
        {}
        // Phase 2D: if the field expression was itself a named-struct aggregate
        // literal with owned subfields, absorb them prefixed with this idx so
        // paths accumulate across nesting levels. Must use a fresh str_cat
        // in both branches so owned_field_idxs never aliases ptok (which is
        // freed by the loop-body scope-exit drop).
        ? & != 0 g_auto_drop_strings != 0 ( nurl_str_len cur_sname )
        { : s sub ( nurl_sym_get syms `__last_agg_owned_fields__` )
            ~ != 0 ( nurl_str_len sub ) {
                : s subtok ( str_first_word sub )
                = sub ( str_skip_word sub )
                = owned_field_idxs ? == 0 ( nurl_str_len owned_field_idxs )
                ( nurl_str_cat3 idx_str `.` subtok )
                ( nurl_str_cat4 owned_field_idxs ` ` idx_str ( nurl_str_cat `.` subtok ) )
            }
        }
        {}

        // For payload fields (idx > 0): conversion depends on aggregate type.
        // opt/res types ({ i1, ... }) need i64 coercion; enum types need ptr coercion.
        : s actual_fval fval
        : s actual_fty fty
        ? > idx 0
        {  // Detect opt/res aggregate: starts with "{ i1, " (6 chars).
            // For opt types the payload field type = T (may be struct %Foo or i64 or i8*).
            // For res types the payload field type is always i64.
            // Only coerce when the expected payload type ≠ value type.
            : b is_opt_res & >= ( nurl_str_len agg_ty ) 6
            ( seq ( nurl_str_slice agg_ty 0 6 ) `{ i1, ` )
            : s payload_ty ? is_opt_res ( compound_field_type agg_ty 1 ) ``
            : b payload_matches & is_opt_res ( seq payload_ty fty )
            ? is_opt_res
            {  // opt/res payload. If value type already matches the payload field
                // type (e.g. `? Node` payload is %Node, value is %Node), no coercion.
                // Otherwise coerce to the payload type — for `! T E` the payload slot
                // is always i64, so string/bool/enum values are folded to i64.
                ? payload_matches
                {}  // value already matches payload_ty: use as-is
                { ? | ( seq fty `i8*` ) ( seq fty `sref` )
                    {  // string → i64 via ptrtoint
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = ptrtoint ` ) ( nurl_print fty ) ( nurl_print ` ` )
                        ( nurl_print fval ) ( nurl_print ` to i64\n` )
                        = actual_fval conv_reg
                        = actual_fty `i64`
                    }
                    ? ( seq fty `i1` )
                    {  // bool → i64 via zext
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = zext i1 ` ) ( nurl_print fval ) ( nurl_print ` to i64\n` )
                        = actual_fval conv_reg
                        = actual_fty `i64`
                    }
                    ? == ( nurl_str_get fty 0 ) 37
                    {  // Named type (starts with '%'). Only treat as struct
                        // handle when the type is NOT an enum — enum payload
                        // slots in `! T E` should stay as the whole enum
                        // value (its i64 tag is extracted by the caller via
                        // ?? match-arm logic, not pre-folded here). This
                        // disambiguation matches gen_agg_lit's earlier
                        // struct-vs-enum branch.
                        : s sname2 ( nurl_str_slice fty 1 - ( nurl_str_len fty ) 1 )
                        : s vlist_a ( nurl_sym_get syms ( nurl_str_cat sname2 `__variants` ) )
                        ? == 0 ( nurl_str_len vlist_a ) {
                            : s f0_ty ( nurl_sym_get syms ( nurl_str_cat3 sname2 `__idx_0` `__type` ) )
                            : b f0_is_ptr & != 0 ( nurl_str_len f0_ty )
                            == ( nurl_str_get f0_ty - ( nurl_str_len f0_ty ) 1 ) 42
                            ? f0_is_ptr
                            {  // Single-pointer-handle struct (Vec, String,
                                // Response, ...): extract f0 + ptrtoint into
                                // the i64 payload slot.
                                : s xv ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print xv )
                                ( nurl_print ` = extractvalue ` ) ( nurl_print fty )
                                ( nurl_print ` ` ) ( nurl_print fval ) ( nurl_print `, 0\n` )
                                : s pi ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print pi )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print f0_ty )
                                ( nurl_print ` ` ) ( nurl_print xv ) ( nurl_print ` to i64\n` )
                                = actual_fval pi }
                            {  // Multi-field / non-pointer-f0 struct: heap-box
                                // the whole struct (alloc, store, ptrtoint)
                                // and stuff the pointer into the i64 slot.
                                // The receiving ?? match arm unboxes via the
                                // wide-struct branch in gen_match.
                                : s sz_reg ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print sz_reg )
                                ( nurl_print ` = getelementptr ` ) ( nurl_print fty )
                                ( nurl_print `, ` ) ( nurl_print fty )
                                ( nurl_print `* null, i32 1\n` )
                                : s sz_int ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print sz_int )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print fty )
                                ( nurl_print `* ` ) ( nurl_print sz_reg ) ( nurl_print ` to i64\n` )
                                : s box_raw ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_raw )
                                ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print sz_int ) ( nurl_print `)` ) ( emit_dbg_eol )
                                : s box_ptr ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_ptr )
                                ( nurl_print ` = bitcast i8* ` ) ( nurl_print box_raw )
                                ( nurl_print ` to ` ) ( nurl_print fty ) ( nurl_print `*\n` )
                                ( nurl_print `  store ` ) ( nurl_print fty )
                                ( nurl_print ` ` ) ( nurl_print fval )
                                ( nurl_print `, ` ) ( nurl_print fty )
                                ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print `\n` )
                                : s box_i ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_i )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print fty )
                                ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print ` to i64\n` )
                                = actual_fval box_i }
                            = actual_fty `i64`
                        } {
                            // Enum flowing into `! T E` payload. If the enum
                            // is "wide" (max_payloads > 0 — its LLVM type is
                            // `{ i64, ptr, ... }` and doesn't fit in 8 bytes)
                            // heap-box it: nurl_alloc(sizeof T), store, then
                            // ptrtoint the pointer into the i64 payload slot.
                            // The receiving ?? match arm does the inverse via
                            // the `__res_nurl_T` reconstruction path.
                            //
                            // Narrow enums (no variant has a payload — only
                            // `{ i64 }`) keep the legacy "fold to tag" path so
                            // existing ParseErr/IoErr-style tag-only enums
                            // round-trip via gen_cast's i64→struct branch.
                            : s mp ( nurl_sym_get syms ( nurl_str_cat sname2 `__max_payloads` ) )
                            : i mp_n ? != 0 ( nurl_str_len mp ) ( nurl_str_to_int mp ) 0
                            ? > mp_n 0 {
                                // Heap-box wide enum.
                                : s sz_reg ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print sz_reg )
                                ( nurl_print ` = getelementptr ` ) ( nurl_print fty )
                                ( nurl_print `, ` ) ( nurl_print fty )
                                ( nurl_print `* null, i32 1\n` )
                                : s sz_int ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print sz_int )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print fty )
                                ( nurl_print `* ` ) ( nurl_print sz_reg ) ( nurl_print ` to i64\n` )
                                : s box_raw ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_raw )
                                ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print sz_int ) ( nurl_print `)` ) ( emit_dbg_eol )
                                : s box_ptr ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_ptr )
                                ( nurl_print ` = bitcast i8* ` ) ( nurl_print box_raw )
                                ( nurl_print ` to ` ) ( nurl_print fty ) ( nurl_print `*\n` )
                                ( nurl_print `  store ` ) ( nurl_print fty )
                                ( nurl_print ` ` ) ( nurl_print fval )
                                ( nurl_print `, ` ) ( nurl_print fty )
                                ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print `\n` )
                                : s box_i ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_i )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print fty )
                                ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print ` to i64\n` )
                                = actual_fval box_i
                            } {
                                // Narrow tag-only enum: extract i64 tag.
                                : s xv ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print xv )
                                ( nurl_print ` = extractvalue ` ) ( nurl_print fty )
                                ( nurl_print ` ` ) ( nurl_print fval ) ( nurl_print `, 0\n` )
                                = actual_fval xv
                            }
                            = actual_fty `i64`
                        }
                    }
                    ? ( seq fty `double` )
                    {  // double → i64 via bitcast (payload slot is i64).
                        // The receiving ?? match arm does the inverse via
                        // bitcast i64→double when reconstructing the value.
                        : s db_bc ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print db_bc )
                        ( nurl_print ` = bitcast double ` ) ( nurl_print fval )
                        ( nurl_print ` to i64\n` )
                        = actual_fval db_bc
                        = actual_fty `i64`
                    }
                    {}  // i64/i32: use as-is
                }
            }
            {  // Check if this is actually an enum type
                // Extract type name from agg_ty (e.g., "%Slice" from "%Slice")
                : s type_name ``
                ? == ( nurl_str_get agg_ty 0 ) 37
                {  // Named type starting with '%' - extract name
                    : i end_pos 1
                    ~ & < end_pos ( nurl_str_len agg_ty ) != ( nurl_str_get agg_ty end_pos ) 32 {
                        = end_pos + end_pos 1
                    }
                    = type_name ( nurl_str_slice agg_ty 1 end_pos )
                }
                {  // Anonymous type like "{ i64*, i64 }" - not an enum
                    = type_name ``
                }

                // Check if it's actually an enum by looking for __variants key
                : s variants_key ( nurl_str_cat type_name `__variants` )
                : s variants_entry ( nurl_sym_get syms variants_key )
                : b is_enum & != 0 ( nurl_str_len type_name ) != 0 ( nurl_str_len variants_entry )

                ? is_enum
                {  // enum payload: convert values to ptr
                    ? ( seq fty `i1` )
                    {  // Convert boolean to i64, then to ptr
                        : s conv_reg1 ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg1 )
                        ( nurl_print ` = zext i1 ` ) ( nurl_print fval ) ( nurl_print ` to i64\n` )
                        : s conv_reg2 ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg2 )
                        ( nurl_print ` = inttoptr i64 ` ) ( nurl_print conv_reg1 ) ( nurl_print ` to ptr\n` )
                        = actual_fval conv_reg2
                        = actual_fty `ptr`
                    }
                    ? | ( seq fty `i64` ) ( seq fty `i32` )
                    {  // Convert integer to ptr
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = inttoptr ` ) ( nurl_print fty ) ( nurl_print ` ` )
                        ( nurl_print fval ) ( nurl_print ` to ptr\n` )
                        = actual_fval conv_reg
                        = actual_fty `ptr`
                    }
                    ? | ( seq fty `sref` ) ( seq fty `i8*` )
                    {  // Convert string to ptr
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = bitcast ` ) ( nurl_print fty ) ( nurl_print ` ` )
                        ( nurl_print fval ) ( nurl_print ` to ptr\n` )
                        = actual_fval conv_reg
                        = actual_fty `ptr`
                    }
                    ? == ( nurl_str_get fty 0 ) 123
                    {  // Anonymous aggregate (e.g., { i1, i64 }): alloca + store + bitcast to ptr
                        : s alloc_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print alloc_reg )
                        ( nurl_print ` = alloca ` ) ( nurl_print fty ) ( nurl_print `\n` )
                        ( nurl_print `  store ` ) ( nurl_print fty ) ( nurl_print ` ` )
                        ( nurl_print fval ) ( nurl_print `, ` ) ( nurl_print fty )
                        ( nurl_print `* ` ) ( nurl_print alloc_reg ) ( nurl_print `\n` )
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = bitcast ` ) ( nurl_print fty ) ( nurl_print `* ` )
                        ( nurl_print alloc_reg ) ( nurl_print ` to ptr\n` )
                        = actual_fval conv_reg
                        = actual_fty `ptr`
                    }
                    ? & == ( nurl_str_get fty 0 ) 37
                        != ( nurl_str_get fty - ( nurl_str_len fty ) 1 ) 42
                    {  // Named NON-POINTER payload (`%Geom`, `%Color`, `%Vec__T`).
                        // A pointer payload (`%Ast*`) is left untouched — the
                        // pointer goes straight into the enum's ptr slot.
                        // (a) single-pointer-handle struct (%Vec__Json,
                        //     %String): field 0 IS a pointer — extract it and
                        //     stash the bare pointer. The match arm rebuilds
                        //     it via insertvalue.
                        // (b) multi-field / non-pointer-f0 struct OR an enum
                        //     (narrow or wide): heap-box the whole value and
                        //     stash the box pointer in the slot. gen_match's
                        //     payload binding loads it back.
                        : s sname3 ( nurl_str_slice fty 1 - ( nurl_str_len fty ) 1 )
                        : s vlist3 ( nurl_sym_get syms ( nurl_str_cat sname3 `__variants` ) )
                        : s f0_ty3 ( nurl_sym_get syms ( nurl_str_cat3 sname3 `__idx_0` `__type` ) )
                        : b is_handle & & == 0 ( nurl_str_len vlist3 )
                            != 0 ( nurl_str_len f0_ty3 )
                            == ( nurl_str_get f0_ty3 - ( nurl_str_len f0_ty3 ) 1 ) 42
                        ? is_handle
                        { : s xv3 ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print xv3 )
                            ( nurl_print ` = extractvalue ` ) ( nurl_print fty )
                            ( nurl_print ` ` ) ( nurl_print fval ) ( nurl_print `, 0\n` )
                            : s pcast ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print pcast )
                            ( nurl_print ` = bitcast ` ) ( nurl_print f0_ty3 )
                            ( nurl_print ` ` ) ( nurl_print xv3 ) ( nurl_print ` to ptr\n` )
                            = actual_fval pcast
                            = actual_fty `ptr` }
                        { : s sz_reg ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print sz_reg )
                            ( nurl_print ` = getelementptr ` ) ( nurl_print fty )
                            ( nurl_print `, ` ) ( nurl_print fty )
                            ( nurl_print `* null, i32 1\n` )
                            : s sz_int ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print sz_int )
                            ( nurl_print ` = ptrtoint ` ) ( nurl_print fty )
                            ( nurl_print `* ` ) ( nurl_print sz_reg ) ( nurl_print ` to i64\n` )
                            : s box_raw ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print box_raw )
                            ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print sz_int ) ( nurl_print `)` ) ( emit_dbg_eol )
                            : s box_ptr ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print box_ptr )
                            ( nurl_print ` = bitcast i8* ` ) ( nurl_print box_raw )
                            ( nurl_print ` to ` ) ( nurl_print fty ) ( nurl_print `*\n` )
                            ( nurl_print `  store ` ) ( nurl_print fty )
                            ( nurl_print ` ` ) ( nurl_print fval )
                            ( nurl_print `, ` ) ( nurl_print fty )
                            ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print `\n` )
                            : s box_cast ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print box_cast )
                            ( nurl_print ` = bitcast ` ) ( nurl_print fty )
                            ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print ` to ptr\n` )
                            = actual_fval box_cast
                            = actual_fty `ptr` }
                    }
                    {}
                }
                {  // Regular struct: preserve field types as-is
                    // No conversion needed - use original fval and fty
                }
            }
        }
        {}

        // Named-struct field: coerce an integer-width mismatch between
        // the value and the field's declared type — e.g. an i64 literal
        // placed in an `i8` / `i16` / `i32` field at construction.
        // `trunc` to a narrower field, `sext` to a wider one. Enum and
        // opt/res aggregates ran their own payload coercion above; an
        // enum has no `__idx_N__type` roster so the lookup is empty and
        // this is skipped. Pointer / float / struct-typed field
        // mismatches are left for an explicit `#`-cast.
        : s decl_fty ? != 0 ( nurl_str_len cur_sname )
            ( nurl_sym_get syms ( nurl_str_cat3 cur_sname
                ( nurl_str_cat `__idx_` idx_str ) `__type` ) )
            ``
        : i decl_iw ( int_width decl_fty )
        : i have_iw ( int_width actual_fty )
        ? & & > decl_iw 0 > have_iw 0 != decl_iw have_iw
        { : s cv ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print cv )
            ( nurl_print ? > decl_iw have_iw ` = sext ` ` = trunc ` )
            ( nurl_print actual_fty ) ( nurl_print ` ` ) ( nurl_print actual_fval )
            ( nurl_print ` to ` ) ( nurl_print decl_fty ) ( nurl_print `\n` )
            = actual_fval cv
            = actual_fty decl_fty }
        {}

        : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = insertvalue ` ) ( nurl_print agg_ty )
        ( nurl_print ` ` ) ( nurl_print result )
        ( nurl_print `, ` ) ( nurl_print actual_fty )
        ( nurl_print ` ` ) ( nurl_print actual_fval )
        ( nurl_print `, ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
        = result r
        = idx + idx 1
    }
    ( expect lex TT_RBRACE )  // consume '}'
    ( nurl_set_last_type agg_ty )
    // Phase 2C: expose the owned-field index list so a binding on the RHS
    // can register drops. Only named-struct aggregates get tracked; anon
    // aggregates like `{ i1, i64 }` are excluded (they have different
    // ownership semantics and our drop helper keys off a `%Name` type).
    ? != 0 g_auto_drop_strings
    { ? == ( nurl_str_get agg_ty 0 ) 37
        { ( nurl_sym_def syms `__last_agg_owned_fields__` owned_field_idxs ) }
        { ( nurl_sym_def syms `__last_agg_owned_fields__` `` ) }
    }
    {}
    // Closure-escape: publish the aggregate-level referent depth. A
    // struct holding a stack-reference field must, when bound or
    // returned, be treated exactly like a bare stack reference —
    // `gen_let_or_struct` copies the depth onto `<name>__refdepth`,
    // and `gen_ret` consults it directly for `^ @ T { ... }`.
    // Composes through nesting: an outer aggregate's field loop sees
    // an inner aggregate's published depth the same way.
    ( nurl_sym_def syms `__last_expr_refdepth__`
        ? > agg_refdepth 0 ( nurl_str_int agg_refdepth ) `` )
    result
}

// ── Slice literal [ type | val* ] ─────────────────────────────────
// Allocates a heap array, stores values, returns { T*, i64 } slice struct.
// Example:  [ i | 10 20 30 ]  →  { i64* ptr, i64 3 }

@ gen_slice_literal i lex i syms i cg → s {
    ( nurl_lex_advance lex )  // consume '['
    : s elem_ty ( parse_type lex )  // e.g. "i64"
    ( expect lex TT_PIPE )  // consume '|'
    // Collect value registers (space-separated) and count
    : s vals ``
    : i count 0
    ~ != ( nurl_lex_type lex ) TT_RBRACK {
        : s v ( gen_expr lex syms cg )
        = vals ? == 0 count v ( nurl_str_cat vals ( nurl_str_cat ` ` v ) )
        = count + count 1
    }
    ( expect lex TT_RBRACK )
    // Compute byte size via LLVM's own GEP+ptrtoint; this is correct for
    // scalars *and* aggregates (e.g. closures are 16 B { fn_ptr, env_ptr },
    // not 8 B).  LLVM folds the expression to a constant.
    : s sz_gep ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print sz_gep )
    ( nurl_print ` = getelementptr ` ) ( nurl_print elem_ty )
    ( nurl_print `, ` ) ( nurl_print elem_ty ) ( nurl_print `* null, i32 ` )
    ( nurl_print ( nurl_str_int count ) ) ( nurl_print `\n` )
    : s sz_i ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print sz_i )
    ( nurl_print ` = ptrtoint ` ) ( nurl_print elem_ty )
    ( nurl_print `* ` ) ( nurl_print sz_gep ) ( nurl_print ` to i64\n` )
    : s raw_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print raw_ptr )
    ( nurl_print ` = call i8* @nurl_malloc(i64 ` )
    ( nurl_print sz_i ) ( nurl_print `)` ) ( emit_dbg_eol )
    // Bitcast i8* → elem_ty*
    : s typed_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print typed_ptr )
    ( nurl_print ` = bitcast i8* ` ) ( nurl_print raw_ptr )
    ( nurl_print ` to ` ) ( nurl_print elem_ty ) ( nurl_print `*\n` )
    // Store each value at successive GEP indices
    : s rest vals
    : i idx 0
    ~ < idx count {
        : s v ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s gep ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print gep )
        ( nurl_print ` = getelementptr ` ) ( nurl_print elem_ty )
        ( nurl_print `, ` ) ( nurl_print elem_ty ) ( nurl_print `* ` )
        ( nurl_print typed_ptr )
        ( nurl_print `, i32 ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
        ( nurl_print `  store ` ) ( nurl_print elem_ty ) ( nurl_print ` ` )
        ( nurl_print v ) ( nurl_print `, ` )
        ( nurl_print elem_ty ) ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
        = idx + idx 1
    }
    // Build { elem_ty*, i64 } slice struct
    : s slice_ty ( nurl_str_cat `{ ` ( nurl_str_cat elem_ty `*, i64 }` ) )
    : s r0 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print r0 )
    ( nurl_print ` = insertvalue ` ) ( nurl_print slice_ty )
    ( nurl_print ` undef, ` ) ( nurl_print elem_ty ) ( nurl_print `* ` )
    ( nurl_print typed_ptr ) ( nurl_print `, 0\n` )
    : s r1 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print r1 )
    ( nurl_print ` = insertvalue ` ) ( nurl_print slice_ty )
    ( nurl_print ` ` ) ( nurl_print r0 )
    ( nurl_print `, i64 ` ) ( nurl_print ( nurl_str_int count ) ) ( nurl_print `, 1\n` )
    ( nurl_set_last_type slice_ty )
    r1
}

// llvm_to_nurl: map LLVM type string to NURL type keyword for error messages.
@ llvm_to_nurl s lt → s {
    ? ( seq lt `i64` ) ^ `i`
    ? ( seq lt `i8` ) ^ `u`
    ? ( seq lt `i1` ) ^ `b`
    ? ( seq lt `double` ) ^ `f`
    ? ( seq lt `i8*` ) ^ `s`
    // Fixed-size types — LLVM doesn't carry signedness, so the reverse
    // map defaults to the signed name (i16 / i32) for diagnostic
    // messages. Unsigned-variant names (u16 / u32 / u64) only appear
    // when the binding's `__nurl_type` is consulted at the call site.
    ? ( seq lt `i16` ) ^ `i16`
    ? ( seq lt `i32` ) ^ `i32`
    ? ( seq lt `float` ) ^ `f32`
    // struct/enum: strip leading '%'
    ? == ( nurl_str_get lt 0 ) 37
    { ^ ( nurl_str_slice lt 1 - ( nurl_str_len lt ) 1 ) }
    {}
    lt
}

// ── Backslash expression disambiguation ──────────────────────────
// '\' is overloaded as closure prefix and try operator.
//   \ →  ...                     → closure (zero params)
//   \ TYPE_KW name ...           → closure
//   \ * | ? | [ | !  inner ...   → closure (typed param)
//   \ ( @ ...                    → closure (fn-type param)
//   \ IDENT IDENT →  ...         → closure (1-param: named type + name + arrow)
//   anything else                → try
// NOTE: we only classify `\ IDENT IDENT` as a closure when the THIRD
// token is '→'. Without that check, `( f \ opt_node fallback )` is
// mis-parsed as a closure because its shape `\ IDENT IDENT` matches.
@ gen_backslash_expr i lex i syms i cg → s {
    ( nurl_lex_advance lex )  // consume '\'
    : i t1 ( nurl_lex_type lex )
    : s t1v ( nurl_lex_val lex )
    : i t2 ( nurl_lex_peek_type lex )
    : i t3 ( nurl_lex_peek2_type lex )
    // Check if t1 is a known type name in the symbol table
    : s t1m ( nurl_sym_get syms ( nurl_str_cat t1v `__is_type` ) )
    : b t1_is_type & == t1 TT_IDENT != 0 ( nurl_str_len t1m )
    // The `\ IDENT name →` 1-param closure form accepts either IDENT or
    // TYPE_KW for the param NAME — single-letter vars (e.g. `s`, `i`)
    // lex as TYPE_KW even though they're valid identifiers in this slot.
    : b t2_is_name | == t2 TT_IDENT == t2 TT_TYPE_KW
    : b is_closure | | | | | == t1 TT_ARROW == t1 TT_TYPE_KW t1_is_type | | | == t1 TT_STAR == t1 TT_QUEST == t1 TT_LBRACK == t1 TT_BANG & == t1 TT_LPAREN == t2 TT_AT & & == t1 TT_IDENT t2_is_name == t3 TT_ARROW
    ? is_closure
    { ^ ( gen_closure_expr lex syms cg ) }
    { ^ ( gen_try_expr lex syms cg ) }
}

// ── Integer width coercion ──────────────────────────────────────
//
// NURL's short-circuit `&` / `|` and comparisons produce an LLVM i1,
// but user variables are typically declared as wider integer types
// (`: i var …` → i64). Storing an i1 into an i64* slot is an LLVM
// verifier error. This helper emits a `zext i1 … to <to_ty>` when the
// source is i1 and the destination is a non-i1 integer type, and is a
// no-op in every other case. Placed here so both the let-binding and
// `=`-assign paths can share it.
@ coerce_store_val s val s from_ty s to_ty i syms i cg → s {
    ? & ( seq from_ty `i1` ) ! ( seq to_ty `i1` )
    { : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = zext i1 ` ) ( nurl_print val )
        ( nurl_print ` to ` ) ( nurl_print to_ty ) ( nurl_print `\n` )
        ^ r
    }
    {}
    // i64 → %Enum: a bare variant name (`Red`, `Green`, `NetOther`, …)
    // resolves through `gen_ident`'s `__global` path to a loaded i64 tag.
    // When the declared LHS is the enum type itself (`: Color c Red` or
    // `: ~ NetErr last_err NetOther`), the raw i64 has to be wrapped into
    // the enum's `{ i64, ptr* }` shape before being stored — otherwise
    // LLVM rejects `store %Color i64, %Color* …`.  Detect enum targets
    // via the registered `<name>__variants` side-table; non-enum named
    // types (structs) fall through unchanged.
    //
    // Closes docs/GOTCHAS.md §3 — `: ~ MyEnum x …` mutable enum binding
    // and the symmetric immutable case. The earlier sentinel-flag-bool
    // workaround in `stdlib/ext/http_server.nu:329–360` is no longer
    // required.
    ? & ( seq from_ty `i64` )
    & != 0 ( nurl_str_len to_ty )
    == ( nurl_str_get to_ty 0 ) 37
    { : s tname ( nurl_str_slice to_ty 1 - ( nurl_str_len to_ty ) 1 )
        : s vlist ( nurl_sym_get syms ( nurl_str_cat tname `__variants` ) )
        ? != 0 ( nurl_str_len vlist )
        { : s r ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print r )
            ( nurl_print ` = insertvalue ` ) ( nurl_print to_ty )
            ( nurl_print ` undef, i64 ` ) ( nurl_print val ) ( nurl_print `, 0\n` )
            ^ r }
        {  // Single-pointer-handle struct (`{ s ctl }`-shape — Vec[A],
           // String, Channel[A], Thread, ArenaImpl). When a Result Ok-arm
           // extract returns the raw i64 payload and the LHS is the
           // handle struct itself, wrap via inttoptr + insertvalue at
           // field 0. Without this, code that does
           //   `: ( Vec u ) v <result-ok-payload>`
           // emits `store %Vec__i8 i64`, an IR type mismatch.
           // Skip if the struct has more than one field (multi-field
           // Result T is heap-boxed at construction so the i64 slot is
           // a heap pointer, not the f0 field value) — those go through
           // the gen_match reconstruction path above.
            : s f0_ty ( nurl_sym_get syms ( nurl_str_cat3 tname `__idx_0` `__type` ) )
            : s f1_ty ( nurl_sym_get syms ( nurl_str_cat3 tname `__idx_1` `__type` ) )
            : b is_single_handle & & != 0 ( nurl_str_len f0_ty )
            == ( nurl_str_get f0_ty - ( nurl_str_len f0_ty ) 1 ) 42
            == 0 ( nurl_str_len f1_ty )
            ? is_single_handle
            { : s p ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print p )
                ( nurl_print ` = inttoptr i64 ` ) ( nurl_print val )
                ( nurl_print ` to ` ) ( nurl_print f0_ty ) ( nurl_print `\n` )
                : s r ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print r )
                ( nurl_print ` = insertvalue ` ) ( nurl_print to_ty )
                ( nurl_print ` undef, ` ) ( nurl_print f0_ty )
                ( nurl_print ` ` ) ( nurl_print p ) ( nurl_print `, 0\n` )
                ^ r }
            {} } }
    {}
    // Integer width adjustment for fixed-size types. Source and dest
    // are both integer LLVM types (i8 / i16 / i32 / i64) and the widths
    // differ. Three cases:
    //   * Narrow (from > to): emit `trunc`.
    //   * Widen, source unsigned (`__last_unsigned__` set by gen_ident
    //     from binding's `__unsigned` flag): emit `zext`.
    //   * Widen, source signed (default): emit `sext`.
    // Shipped 2026-05-14 with the fixed-size types Phase 1 — `: i32 x 5`,
    // `: i32 width  ( fn → i32 )`, and FFI-style narrow returns now store
    // cleanly without manual `# T` casts. Float-width adjustment (f32 ↔
    // double) lives in gen_cast since it needs explicit `#` syntax.
    : i fw ( int_width from_ty )
    : i tw ( int_width to_ty )
    ? & & > fw 0 > tw 0 != fw tw
    { ? > fw tw
        { : s r ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print r )
            ( nurl_print ` = trunc ` ) ( nurl_print from_ty )
            ( nurl_print ` ` ) ( nurl_print val )
            ( nurl_print ` to ` ) ( nurl_print to_ty ) ( nurl_print `\n` )
            ^ r }
        { : s lu ( nurl_sym_get syms `__last_unsigned__` )
            : s inst ? != 0 ( nurl_str_len lu ) `zext` `sext`
            : s r ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print r )
            ( nurl_print ` = ` ) ( nurl_print inst ) ( nurl_print ` ` )
            ( nurl_print from_ty ) ( nurl_print ` ` ) ( nurl_print val )
            ( nurl_print ` to ` ) ( nurl_print to_ty ) ( nurl_print `\n` )
            ^ r } }
    {}
    val
}

// Narrow a wider integer to i1 for use as a branch condition. The NURL
// `?` / `~` constructs accept any integer expression as a condition
// (non-zero ⇒ true), but LLVM's `br` requires i1. When the user writes
// `? & can_l can_r { … }` with i64 operands, the `&` lowers to
// `and i64` — this helper emits `icmp ne i64 %v, 0` to produce the
// required i1. No-op when the value is already i1.
@ coerce_to_i1 s val s ty i cg → s {
    ? ( seq ty `i1` )
    { val }
    { : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = icmp ne ` ) ( nurl_print ty )
        ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, 0\n` )
        r
    }
}

// ── Closure call site helpers ───────────────────────────────────

// Convert closure struct to function pointer if needed
@ convert_closure_arg s arg_val s arg_type s expected_type i cg → s {
    // Simple type checking: check if we need to convert closure struct to function pointer
    : b is_closure_struct != 0 ( nurl_str_starts arg_type `{` )
    // Check if expected type looks like a function pointer (any return type)
    : b starts_with_fn != 0 ( nurl_str_starts expected_type `i64 (` )
    : b starts_with_void != 0 ( nurl_str_starts expected_type `void (` )
    : b starts_with_i8 != 0 ( nurl_str_starts expected_type `i8* (` )
    : b starts_with_i32 != 0 ( nurl_str_starts expected_type `i32 (` )
    : b starts_with_dbl != 0 ( nurl_str_starts expected_type `double (` )
    : b expects_fn_ptr | | | starts_with_fn starts_with_void starts_with_i8 | starts_with_i32 starts_with_dbl

    ( nurl_print `  ; DEBUG: convert_closure_arg is_closure=` ) ( nurl_print ? is_closure_struct `1` `0` ) ( nurl_print ` expects_fn=` ) ( nurl_print ? expects_fn_ptr `1` `0` ) ( nurl_print `\n` )

    ? & is_closure_struct expects_fn_ptr
    {
        // Extract function pointer from closure struct (field 0)
        : s fn_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ; Converting closure struct to function pointer\n` )
        ( nurl_print `  ` ) ( nurl_print fn_ptr )
        ( nurl_print ` = extractvalue ` ) ( nurl_print arg_type )
        ( nurl_print ` ` ) ( nurl_print arg_val ) ( nurl_print `, 0\n` )
        fn_ptr
    }
    { arg_val }  // No conversion needed
}

// ── Closure deferral helpers ─────────────────────────────────────

// Store a closure type definition for later emission
@ store_closure_type s typedef → v {
    : i types_syms g_closure_types
    ( nurl_sym_def types_syms ( nurl_str_int g_type_count ) typedef )
    = g_type_count + g_type_count 1
}

// Store a closure function definition for later emission
@ store_closure_func s funcdef → v {
    : i defs_syms g_closure_defs
    ( nurl_sym_def defs_syms ( nurl_str_int g_func_count ) funcdef )
    = g_func_count + g_func_count 1
}

// ── Environment struct generation for closures ──────────────────

// Generate a struct type definition for captured variables
// Build an inline struct type string for the env:
//   { i64, T1, T2, ..., Tn }
// Field 0 is the refcount (i64). Fields 1..N use each captured
// variable's NATIVE LLVM type — i64 for ints, i1 for bools, i8* for
// raw pointers, %Vec__i64 / %Set__str / etc. for struct handles, and
// `{ R(i8*, P*)*, i8* }` for captured closures. This avoids forcing
// every value through ptrtoint→i64 (which LLVM rejects for aggregate
// types like struct handles and closure structs).
//
// Returns the inline type string (e.g., "{ i64, i64, %Set__i64 }").
// No named struct types — avoids LLVM forward-reference ordering issues.
// Detect "capture by pointer" eligibility for a captured variable. A
// captured var is taken by pointer when ALL of the following hold:
//   * The binding was declared mutable (`: ~ T name init` — has
//     `<name>__mutable` set in syms)
//   * Its type is a named struct (`%T`, not an enum — no `__variants`
//     entry, and not an opaque single-pointer-handle struct)
//   * The struct has at least two fields (a `__idx_1__type` entry
//     exists in syms) — single-field handle structs like %String /
//     %Vec already share through their inner pointer, so capturing
//     by value preserves mutation visibility.
// Closes docs/GOTCHAS.md §2 — `=` writes through a captured Counter
// land on the caller's alloca instead of a dead local copy.
@ __is_capture_byref s var i syms → b {
    : s mut ( nurl_sym_get syms ( nurl_str_cat var `__mutable` ) )
    ? == 0 ( nurl_str_len mut ) { ^ F } {}
    : s vt ( nurl_sym_get syms var )
    ? == 0 ( nurl_str_len vt ) { ^ F } {}
    ? != ( nurl_str_get vt 0 ) 37 { ^ F } {}
    : s tname ( nurl_str_slice vt 1 - ( nurl_str_len vt ) 1 )
    : s vlist ( nurl_sym_get syms ( nurl_str_cat tname `__variants` ) )
    ? != 0 ( nurl_str_len vlist ) { ^ F } {}
    : s f1 ( nurl_sym_get syms ( nurl_str_cat3 tname `__idx_1` `__type` ) )
    ? == 0 ( nurl_str_len f1 ) { ^ F } {}
    ^ T
}

@ gen_env_struct_type s struct_name s captured_vars i syms → s {
    ? == 0 ( count_words captured_vars )
    { ^ `` }  // No captures
    {}

    : s ty `{ i64`  // field 0: refcount
    : s vars captured_vars
    ~ != 0 ( nurl_str_len vars ) {
        : s var ( str_first_word vars )
        : s vt ( nurl_sym_get syms var )
        ? == 0 ( nurl_str_len vt ) { = vt `i64` } {}
        // Mutable multi-field structs are captured by pointer so writes
        // through the closure observe the caller's alloca.
        ? ( __is_capture_byref var syms ) { = vt ( nurl_str_cat vt `*` ) } {}
        = ty ( nurl_str_cat ty ( nurl_str_cat `, ` vt ) )
        = vars ( str_skip_word vars )
    }
    = ty ( nurl_str_cat ty ` }` )
    ty
}

// Generate code to allocate and populate environment struct.
// struct_name is the inline struct type (e.g., "{ i64, i64, %Set__i64 }").
// Each captured variable is loaded from its stack alloca and stored
// via its NATIVE LLVM type — no ptrtoint/zext/trunc shimming. Aggregate
// types (struct handles, captured closures) flow through unchanged.
//
// Allocation size is computed from the LLVM type itself via the
// "GEP on null at index 1" trick: `getelementptr T, T* null, i32 1`
// produces a pointer offset by sizeof(T) bytes, which we then ptrtoint
// to an i64 byte count and pass to nurl_malloc.
@ gen_env_allocation s struct_name s captured_vars i syms i cg → s {
    ? == 0 ( count_words captured_vars )
    { ^ `null` }
    {}

    // Compute sizeof(struct_name) at IR-emission time via GEP-on-null.
    : s size_gep ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print size_gep )
    ( nurl_print ` = getelementptr ` ) ( nurl_print struct_name )
    ( nurl_print `, ` ) ( nurl_print struct_name ) ( nurl_print `* null, i32 1\n` )
    : s size_i64 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print size_i64 )
    ( nurl_print ` = ptrtoint ` ) ( nurl_print struct_name ) ( nurl_print `* ` )
    ( nurl_print size_gep ) ( nurl_print ` to i64\n` )

    : s env_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print env_ptr )
    ( nurl_print ` = call i8* @nurl_malloc(i64 ` )
    ( nurl_print size_i64 ) ( nurl_print `)` ) ( emit_dbg_eol )

    : s typed_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print typed_ptr )
    ( nurl_print ` = bitcast i8* ` ) ( nurl_print env_ptr )
    ( nurl_print ` to ` ) ( nurl_print struct_name ) ( nurl_print `*\n` )

    // Store refcount = 1 in field 0
    : s refcount_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print refcount_ptr )
    ( nurl_print ` = getelementptr ` ) ( nurl_print struct_name )
    ( nurl_print `, ` ) ( nurl_print struct_name ) ( nurl_print `* ` )
    ( nurl_print typed_ptr ) ( nurl_print `, i32 0, i32 0\n` )
    ( nurl_print `  store i64 1, i64* ` ) ( nurl_print refcount_ptr ) ( nurl_print `\n` )

    // Store each captured variable directly with its native type in
    // fields 1..N. No conversion: store T %val, T* %fp.
    // Mutable multi-field structs (`__is_capture_byref`) store the
    // ALLOCA POINTER itself — the env field type is `T*`, the body
    // reads the pointer back and uses it as the var's `__ptr` so
    // every read/write reaches the caller's alloca.
    : s vars captured_vars
    : i field_idx 1
    ~ != 0 ( nurl_str_len vars ) {
        : s var ( str_first_word vars )
        : s var_type ( nurl_sym_get syms var )
        : s var_alloca ( nurl_sym_get syms ( nurl_str_cat var `__ptr` ) )
        : b cap_byref ( __is_capture_byref var syms )

        // Effective env-field type and the value we store there.
        : s eff_type ? cap_byref ( nurl_str_cat var_type `*` ) var_type
        : s loaded ( nurl_cg_reg cg )
        ? cap_byref
        {  // Store the alloca pointer itself — no load, no copy.
            = loaded var_alloca }
        {  // Existing path: load the variable's current value.
            ? != 0 ( nurl_str_len var_alloca )
            { ( nurl_print `  ` ) ( nurl_print loaded )
                ( nurl_print ` = load ` ) ( nurl_print var_type )
                ( nurl_print `, ` ) ( nurl_print var_type )
                ( nurl_print `* ` ) ( nurl_print var_alloca ) ( nurl_print `\n` ) }
            { = loaded ( nurl_str_cat `%` var ) }
        }

        // GEP to field and store with the effective type.
        : s store_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print store_ptr )
        ( nurl_print ` = getelementptr ` ) ( nurl_print struct_name )
        ( nurl_print `, ` ) ( nurl_print struct_name ) ( nurl_print `* ` )
        ( nurl_print typed_ptr ) ( nurl_print `, i32 0, i32 ` )
        ( nurl_print ( nurl_str_int field_idx ) ) ( nurl_print `\n` )
        ( nurl_print `  store ` ) ( nurl_print eff_type ) ( nurl_print ` ` )
        ( nurl_print loaded ) ( nurl_print `, ` ) ( nurl_print eff_type )
        ( nurl_print `* ` ) ( nurl_print store_ptr ) ( nurl_print `\n` )

        = vars ( str_skip_word vars )
        = field_idx + field_idx 1
    }

    env_ptr
}

// Generate code to increment environment reference count
@ gen_env_inc_ref s env_ptr s struct_name i cg → v {
    ? != 0 ( nurl_str_eq env_ptr `null` )
    {}
    {
        // Cast environment pointer to proper type if needed
        : s typed_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print typed_ptr )
        ( nurl_print ` = bitcast i8* ` ) ( nurl_print env_ptr )
        ( nurl_print ` to ` ) ( nurl_print struct_name ) ( nurl_print `*\n` )

        // Get pointer to reference count field (field 0)
        : s refcount_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print refcount_ptr )
        ( nurl_print ` = getelementptr ` ) ( nurl_print struct_name )
        ( nurl_print `, ` ) ( nurl_print struct_name ) ( nurl_print `* ` )
        ( nurl_print typed_ptr ) ( nurl_print `, i64 0, i32 0\n` )

        // Load current reference count
        : s old_count ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print old_count )
        ( nurl_print ` = load i64, i64* ` ) ( nurl_print refcount_ptr ) ( nurl_print `\n` )

        // Increment and store back
        : s new_count ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print new_count )
        ( nurl_print ` = add i64 ` ) ( nurl_print old_count ) ( nurl_print `, 1\n` )
        ( nurl_print `  store i64 ` ) ( nurl_print new_count )
        ( nurl_print `, i64* ` ) ( nurl_print refcount_ptr ) ( nurl_print `\n` )
    }
}

// Generate code to decrement environment reference count and deallocate if needed
@ gen_env_dec_ref s env_ptr s struct_name i cg → v {
    ? != 0 ( nurl_str_eq env_ptr `null` )
    {}
    {

        // Cast environment pointer to proper type if needed
        : s typed_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print typed_ptr )
        ( nurl_print ` = bitcast i8* ` ) ( nurl_print env_ptr )
        ( nurl_print ` to ` ) ( nurl_print struct_name ) ( nurl_print `*\n` )

        // Get pointer to reference count field (field 0)
        : s refcount_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print refcount_ptr )
        ( nurl_print ` = getelementptr ` ) ( nurl_print struct_name )
        ( nurl_print `, ` ) ( nurl_print struct_name ) ( nurl_print `* ` )
        ( nurl_print typed_ptr ) ( nurl_print `, i64 0, i32 0\n` )

        // Load current reference count
        : s old_count ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print old_count )
        ( nurl_print ` = load i64, i64* ` ) ( nurl_print refcount_ptr ) ( nurl_print `\n` )

        // Decrement reference count
        : s new_count ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print new_count )
        ( nurl_print ` = sub i64 ` ) ( nurl_print old_count ) ( nurl_print `, 1\n` )
        ( nurl_print `  store i64 ` ) ( nurl_print new_count )
        ( nurl_print `, i64* ` ) ( nurl_print refcount_ptr ) ( nurl_print `\n` )

        // Check if reference count reached zero
        : s is_zero ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print is_zero )
        ( nurl_print ` = icmp eq i64 ` ) ( nurl_print new_count ) ( nurl_print `, 0\n` )

        // Generate labels for conditional deallocation
        : s dealloc_label ( nurl_cg_lbl cg `dealloc_env` )
        : s continue_label ( nurl_cg_lbl cg `continue` )

        // Branch based on reference count
        ( nurl_print `  br i1 ` ) ( nurl_print is_zero )
        ( nurl_print `, label %` ) ( nurl_print dealloc_label )
        ( nurl_print `, label %` ) ( nurl_print continue_label ) ( emit_dbg_eol )

        // Deallocation block
        ( nurl_print dealloc_label ) ( nurl_print `:\n` )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print env_ptr ) ( nurl_print `)` ) ( emit_dbg_eol )
        ( nurl_print `  br label %` ) ( nurl_print continue_label ) ( emit_dbg_eol )

        // Continue block
        ( nurl_print continue_label ) ( nurl_print `:\n` )
    }
}

// ── Closure expression \ param* → type { ... } ───────────────────
// Generates a function pointer value that captures local variables
// NOTE: Expects backslash to already be consumed by disambiguation function
@ gen_closure_expr i lex i syms i cg → s {

    // Parse parameters: type name pairs before arrow
    : s param_types ``
    : s param_names ``
    : i param_count 0

    // Parse parameters until we see arrow
    ~ != ( nurl_lex_type lex ) TT_ARROW {
        // Parse one parameter: type name
        : s pty ( parse_type lex )

        ? ! ( is_ident_tok ( nurl_lex_type lex ) )
        { ( die lex `expected parameter name after type` ) }
        {}

        : s pname ( nurl_lex_val lex )
        ( nurl_lex_advance lex )

        // Add to parameter lists
        = param_types ? == 0 param_count
        pty
        ( nurl_str_cat ( nurl_str_cat param_types ` ` ) pty )
        = param_names ? == 0 param_count
        pname
        ( nurl_str_cat ( nurl_str_cat param_names ` ` ) pname )
        = param_count + param_count 1
    }

    ( expect lex TT_ARROW )  // consume →
    : s ret_type ( parse_type lex )

    // Generate unique closure function name (use a simple counter approach)
    = g_func_count + g_func_count 1
    : s closure_fn_name ( nurl_str_cat `__closure_` ( nurl_str_int g_func_count ) )

    // Analyze closure body for captured variables
    ? != ( nurl_lex_type lex ) TT_LBRACE
    { ( die lex `expected { after closure return type` ) }
    {}

    // Save lexer position at the opening '{' so we can re-parse the body
    : i body_start_pos ( nurl_lex_cur_start lex )

    // syms is the OUTER scope; param_names is a space-separated list of closure params.
    // Only outer locals (those with __ptr in syms) are captured, not globals/functions.
    : s captured_vars ( simple_capture_analysis lex syms param_names )
    : i captured_count ( count_words captured_vars )

    // Build inline env struct type (e.g., "{ i64, i64 }") if there are captures.
    // Using inline types avoids LLVM named-struct forward-reference issues.
    : s env_struct_name ``
    ? > captured_count 0
    { = env_struct_name ( gen_env_struct_type `` captured_vars syms ) }
    { = env_struct_name `null` }

    // ── Compile the actual closure body ──
    // Redirect nurl_print to a buffer so we can capture the body IR as a string
    ( nurl_print_buf_reset )
    ( nurl_print_buf_start )

    // DWARF: enter a fresh subprogram scope for the closure. The
    // closure's own DISubprogram references the enclosing fn's
    // subprogram so backtraces resolve a closure call through the
    // surrounding scope. Saved subprogram/loc are restored after the
    // body is buffered; the enclosing fn's instructions resume with
    // their original `!dbg !N` attachments.
    : i saved_dbg_sp g_dbg_current_subprogram
    : i saved_dbg_loc g_dbg_current_loc
    : i closure_sp_id 0
    ? != g_dbg_enabled 0
    { = closure_sp_id ( dbg_emit_subprogram closure_fn_name ( nurl_lex_line lex ) )
        = g_dbg_current_subprogram closure_sp_id
        = g_dbg_current_loc ( dbg_emit_location ( nurl_lex_line lex ) 1 closure_sp_id ) }
    {}

    // Emit function header
    ( nurl_print `\ndefine ` ) ( nurl_print ret_type ) ( nurl_print ` @` )
    ( nurl_print closure_fn_name ) ( nurl_print `(i8* %__env` )
    : s body_param_types param_types
    : s body_param_names param_names
    : i bi 0
    ~ < bi param_count {
        ( nurl_print `, ` )
        : s bpty ( str_first_word body_param_types )
        : s bpname ( str_first_word body_param_names )
        ( nurl_print bpty ) ( nurl_print ` %` ) ( nurl_print bpname )
        = body_param_types ( str_skip_word body_param_types )
        = body_param_names ( str_skip_word body_param_names )
        = bi + bi 1
    }
    ( nurl_print `)` )
    ? != g_dbg_enabled 0
    { ( nurl_print ` !dbg !` ) ( nurl_print ( nurl_str_int closure_sp_id ) ) }
    {}
    ( nurl_print ` {\nentry:\n` )

    // Build closure body symtable: copy outer scope + add params + captured vars
    ( nurl_sym_push syms )
    : i body_syms syms
    // Shadow outer __owned_slices__ with empty list for the closure body
    ( nurl_sym_def body_syms `__owned_slices__` `` )
    // Defers don't cross closure boundaries — clear shadow too
    ( nurl_sym_def body_syms `__defer_top__` `` )
    // Reset the shadow-check roster so a `:` inside the closure body
    // checks against the closure's OWN params, not the enclosing
    // function's. Restored on sym_pop at the bottom of this function.
    ( nurl_sym_def body_syms `__fn_param_names__` `` )

    // Register closure parameters
    : s bp_types param_types
    : s bp_names param_names
    : i bpi 0
    ~ < bpi param_count {
        : s bpname ( str_first_word bp_names )
        : s bptype ( str_first_word bp_types )
        // Alloca for each param so it can be loaded
        : s bpptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print bpptr )
        ( nurl_print ` = alloca ` ) ( nurl_print bptype ) ( nurl_print `\n` )
        ( nurl_print `  store ` ) ( nurl_print bptype ) ( nurl_print ` %` )
        ( nurl_print bpname ) ( nurl_print `, ` ) ( nurl_print bptype )
        ( nurl_print `* ` ) ( nurl_print bpptr ) ( nurl_print `\n` )
        ( nurl_sym_def body_syms bpname bptype )
        ( nurl_sym_def body_syms ( nurl_str_cat bpname `__ptr` ) bpptr )
        ( nurl_sym_def body_syms ( nurl_str_cat bpname `__param` ) `1` )
        // Mirror into the closure-local shadow-check roster.
        : s c_name_roster ( nurl_sym_get body_syms `__fn_param_names__` )
        : s c_name_next ? == 0 ( nurl_str_len c_name_roster ) bpname ( nurl_str_cat3 c_name_roster ` ` bpname )
        ( nurl_sym_def body_syms `__fn_param_names__` c_name_next )
        = bp_types ( str_skip_word bp_types )
        = bp_names ( str_skip_word bp_names )
        = bpi + bpi 1
    }

    // Register captured variables via environment struct.
    // A by-pointer capture (mutable multi-field struct) makes this
    // closure carry a pointer into the enclosing function's stack,
    // so it must NOT outlive that frame. The borrow checker's escape
    // analysis (BORROW.md Phase 3) tags the closure value with a
    // *referent depth* — the deepest block scope it points into — so
    // gen_let / gen_assign / gen_ret / gen_call reject escapes
    // (docs/GOTCHAS.md §8).
    : ~ i closure_refdepth 0
    ? > captured_count 0
    {
        : s typed_env ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print typed_env )
        ( nurl_print ` = bitcast i8* %__env to ` ) ( nurl_print env_struct_name )
        ( nurl_print `*\n` )
        // Extract each captured variable (fields 1, 2, ... — field 0 is refcount).
        // Two shapes:
        //   * By-value (default): load with native type, alloca + store so the
        //     body sees a mutable local of type cap_type. Mutations stay local.
        //   * By-pointer (mutable multi-field structs, `__is_capture_byref`):
        //     the env field IS the caller's alloca pointer. Load the pointer
        //     and register it as the body's `<cap>__ptr` directly — every
        //     read/write inside the closure body reaches the caller's
        //     allocation through this shared pointer. The body sees the same
        //     binding shape (`__ptr` + native type), so no other path needs
        //     to special-case it. Closes docs/GOTCHAS.md §2.
        : s caps captured_vars
        : i cap_idx 1
        ~ != 0 ( nurl_str_len caps ) {
            : s cap_name ( str_first_word caps )
            : s cap_type ( nurl_sym_get syms cap_name )
            ? == 0 ( nurl_str_len cap_type ) { = cap_type `i64` } {}
            : b cap_byref ( __is_capture_byref cap_name syms )
            // Escape analysis: a by-pointer capture references
            // `cap_name`'s stack slot — its declaration depth
            // (`<cap>__bdepth`, defaulting to the function body, 1,
            // for a parameter) constrains this closure's lifetime.
            // Capturing a binding that is ITSELF a stack reference
            // (`<cap>__refdepth`) propagates that depth transitively
            // (a closure-of-a-closure). The closure's referent depth
            // is the deepest such constraint.
            ? & != g_borrowck 0 cap_byref {
                : s cbd ( nurl_sym_get syms ( nurl_str_cat cap_name `__bdepth` ) )
                : i cbdv ? == 0 ( nurl_str_len cbd ) 1 ( nurl_str_to_int cbd )
                ? > cbdv closure_refdepth { = closure_refdepth cbdv } {}
            } {}
            ? != g_borrowck 0 {
                : s crd ( nurl_sym_get syms ( nurl_str_cat cap_name `__refdepth` ) )
                ? != 0 ( nurl_str_len crd ) {
                    : i crdv ( nurl_str_to_int crd )
                    ? > crdv closure_refdepth { = closure_refdepth crdv } {}
                } {}
            } {}
            : s eff_type ? cap_byref ( nurl_str_cat cap_type `*` ) cap_type
            : s cap_gep ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print cap_gep )
            ( nurl_print ` = getelementptr ` ) ( nurl_print env_struct_name )
            ( nurl_print `, ` ) ( nurl_print env_struct_name ) ( nurl_print `* ` )
            ( nurl_print typed_env ) ( nurl_print `, i32 0, i32 ` )
            ( nurl_print ( nurl_str_int cap_idx ) ) ( nurl_print `\n` )
            : s cap_val ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print cap_val )
            ( nurl_print ` = load ` ) ( nurl_print eff_type )
            ( nurl_print `, ` ) ( nurl_print eff_type )
            ( nurl_print `* ` ) ( nurl_print cap_gep ) ( nurl_print `\n` )
            ? cap_byref
            {  // The loaded value IS the caller's alloca pointer.
                ( nurl_sym_def body_syms cap_name cap_type )
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__ptr` ) cap_val )
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__mutable` ) `1` ) }
            {  // Existing path: alloca + store so the body sees a local.
                : s cap_ptr ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print cap_ptr )
                ( nurl_print ` = alloca ` ) ( nurl_print cap_type ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print cap_type ) ( nurl_print ` ` )
                ( nurl_print cap_val ) ( nurl_print `, ` ) ( nurl_print cap_type )
                ( nurl_print `* ` ) ( nurl_print cap_ptr ) ( nurl_print `\n` )
                ( nurl_sym_def body_syms cap_name cap_type )
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__ptr` ) cap_ptr )
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__mutable` ) `1` ) }
            = caps ( str_skip_word caps )
            = cap_idx + cap_idx 1
        }
    }
    {}

    // Restore lexer to the '{' and compile the real body
    ( nurl_lex_set_pos lex body_start_pos )
    : i outer_did_ret g_did_ret
    = g_did_ret 0
    // Borrow checker (Phase 1): suppress capture inside the closure
    // body — its statements must not inline into the enclosing
    // function's list (where they would conflate same-named bindings).
    = g_bck_closure_depth + g_bck_closure_depth 1
    : s body_val ( gen_stmt lex body_syms cg )
    = g_bck_closure_depth - g_bck_closure_depth 1

    // Emit return
    ? == g_did_ret 0
    {
        ? ( seq ret_type `void` )
        { ( nurl_print `  ret void` ) ( emit_dbg_eol ) }
        { ( nurl_print `  ret ` ) ( nurl_print ret_type ) ( nurl_print ` ` )
            ( nurl_print body_val ) ( emit_dbg_eol )
        }
    }
    {}
    ( nurl_print `}\n` )
    = g_did_ret outer_did_ret

    ( nurl_sym_pop syms )

    // Stop capturing and store as deferred closure function
    : s funcdef ( nurl_print_buf_stop )
    ( store_closure_func funcdef )
    // Restore the enclosing function's DWARF context — subsequent
    // instructions emitted by gen_stmt continue under its DISubprogram.
    = g_dbg_current_subprogram saved_dbg_sp
    = g_dbg_current_loc saved_dbg_loc

    // Return a function pointer constant
    : s fn_ptr_type ( nurl_str_cat `{ ` ( nurl_str_cat ret_type `(` ) )
    = fn_ptr_type ( nurl_str_cat fn_ptr_type `i8*` )
    : s types1 param_types
    : i j 0
    ~ < j param_count {
        = fn_ptr_type ( nurl_str_cat ( nurl_str_cat fn_ptr_type `, ` ) ( str_first_word types1 ) )
        = types1 ( str_skip_word types1 )
        = j + j 1
    }
    = fn_ptr_type ( nurl_str_cat fn_ptr_type `)*, i8* }` )

    // Allocate and populate environment if there are captures
    : s env_ptr `null`
    ? > captured_count 0
    {
        = env_ptr ( gen_env_allocation env_struct_name captured_vars syms cg )
    }
    {}

    // Initialize closure struct using insertvalue with undef
    : s result ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print result )
    ( nurl_print ` = insertvalue ` ) ( nurl_print fn_ptr_type )
    ( nurl_print ` undef, ` ) ( nurl_print ret_type ) ( nurl_print `(i8*` )
    : s types2 param_types
    : i k 0
    ~ < k param_count {
        ( nurl_print `, ` ) ( nurl_print ( str_first_word types2 ) )
        = types2 ( str_skip_word types2 )
        = k + k 1
    }
    ( nurl_print `)* @` ) ( nurl_print closure_fn_name ) ( nurl_print `, 0\n` )

    : s result2 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print result2 )
    ( nurl_print ` = insertvalue ` ) ( nurl_print fn_ptr_type )
    ( nurl_print ` ` ) ( nurl_print result ) ( nurl_print `, i8* ` )
    ( nurl_print env_ptr ) ( nurl_print `, 1\n` )

    ( nurl_set_last_type fn_ptr_type )

    // Escape analysis (BORROW.md Phase 3): advertise this closure
    // value's referent depth on `__last_expr_refdepth__` whenever it
    // captures a stack binding by pointer (directly, or transitively
    // via another captured reference). The consuming gen_let /
    // gen_assign / gen_ret / gen_call resets this side-channel before
    // `gen_expr` and reads it after, so it never bleeds into a
    // sibling expression. No-op when --borrowck is off
    // (closure_refdepth stays 0).
    ? > closure_refdepth 0
    { ( nurl_sym_def syms `__last_expr_refdepth__`
        ( nurl_str_int closure_refdepth ) ) }
    {}

    result2
}

// ── String Helpers ───────────────────────────────────────────────
// Count words in a space-separated string
@ count_words s word_list → i {
    ? == 0 ( nurl_str_len word_list ) ^ 0 {}

    : i count 0
    : s remaining word_list
    ~ != 0 ( nurl_str_len remaining ) {
        = remaining ( str_skip_word remaining )
        = count + count 1
    }
    count
}

// Check if a space-separated word list contains a specific word
@ str_contains s word_list s target → b {
    ? == 0 ( nurl_str_len word_list ) ^ F {}

    : s remaining word_list
    ~ != 0 ( nurl_str_len remaining ) {
        : s current_word ( str_first_word remaining )
        ? ( seq current_word target ) ^ T {}
        = remaining ( str_skip_word remaining )
    }
    F
}

// ── Simple Capture Analysis ─────────────────────────────────────
// Returns a space-separated string of captured variable names

@ simple_capture_analysis i lex i outer_syms s closure_params → s {
    : s captured_vars ``
    : i captured_count 0
    ( nurl_lex_advance lex )  // consume opening '{'

    // Scan tokens in closure body until closing brace
    : i brace_depth 1
    ~ > brace_depth 0 {
        : i tt ( nurl_lex_type lex )

        ? == tt TT_LBRACE
        { = brace_depth + brace_depth 1 }
        {
            ? == tt TT_RBRACE
            { = brace_depth - brace_depth 1 }
            {
                // Check for assignment to immutable variables
                ? == tt TT_EQ
                {
                    ( nurl_lex_advance lex )  // consume '='
                    ? | == ( nurl_lex_type lex ) TT_IDENT == ( nurl_lex_type lex ) TT_TYPE_KW
                    {
                        : s target_var ( nurl_lex_val lex )
                        // Only check mutability for outer-scope LOCAL variables (have __ptr)
                        : s outer_ptr ( nurl_sym_get outer_syms ( nurl_str_cat target_var `__ptr` ) )
                        ? != 0 ( nurl_str_len outer_ptr )
                        {
                            : s param_marker ( nurl_sym_get outer_syms ( nurl_str_cat target_var `__param` ) )
                            : b is_param != 0 ( nurl_str_len param_marker )
                            ? is_param
                            { ( die lex ( nurl_str_cat `cannot mutate immutable parameter: ` target_var ) ) }
                            {
                                : s mut_marker ( nurl_sym_get outer_syms ( nurl_str_cat target_var `__mutable` ) )
                                ? == 0 ( nurl_str_len mut_marker )
                                { ( die lex ( nurl_str_cat `cannot mutate immutable variable: ` target_var ) ) }
                                {}
                            }
                            // Assignment counts as a USE of `target_var`
                            // from the outer scope — the env block must
                            // carry the binding's pointer so the closure
                            // body can store through it. Without this the
                            // body emits `store … %rNN` referencing the
                            // outer's alloca register directly, producing
                            // invalid IR (use of undefined value).
                            : b is_clo_param_t ( str_contains closure_params target_var )
                            ? ! is_clo_param_t {
                                ? ! ( str_contains captured_vars target_var ) {
                                    = captured_vars ? == 0 captured_count
                                    target_var
                                    ( nurl_str_cat ( nurl_str_cat captured_vars ` ` ) target_var )
                                    = captured_count + captured_count 1
                                } {}
                            } {}
                        }
                        {}
                    }
                    {}
                }
                {
                    // Capture identifier if it is an outer local/param and not a closure param
                    ? | == tt TT_IDENT == tt TT_TYPE_KW
                    {
                        : s var_name ( nurl_lex_val lex )
                        // Skip closure parameters
                        : b is_clo_param ( str_contains closure_params var_name )
                        ? ! is_clo_param
                        {
                            // Capture locals (have __ptr) and outer fn params (have __param)
                            : s outer_ptr ( nurl_sym_get outer_syms ( nurl_str_cat var_name `__ptr` ) )
                            : s outer_param ( nurl_sym_get outer_syms ( nurl_str_cat var_name `__param` ) )
                            ? | != 0 ( nurl_str_len outer_ptr ) != 0 ( nurl_str_len outer_param )
                            {
                                ? ! ( str_contains captured_vars var_name )
                                {
                                    = captured_vars ? == 0 captured_count
                                    var_name
                                    ( nurl_str_cat ( nurl_str_cat captured_vars ` ` ) var_name )
                                    = captured_count + captured_count 1
                                }
                                {}
                            }
                            {}
                        }
                        {}
                    }
                    {}
                }
            }
        }

        ? == tt TT_EOF
        { = brace_depth 0 }  // Break on EOF
        { ( nurl_lex_advance lex ) }
    }
    // Lexer is now positioned after closing brace
    captured_vars
}

// ── Closure Body Generation Helpers ──────────────────────────────

// Extract the result register from body code (simple pattern matching)
@ extract_body_result s body_code → s {
    // Look for patterns like "%rX = " to find the last register assigned
    // Check for various register numbers
    ? ( str_contains body_code `%r7` )
    { `%r7` }
    { ? ( str_contains body_code `%r6` )
        { `%r6` }
        { ? ( str_contains body_code `%r5` )
            { `%r5` }
            { ? ( str_contains body_code `%r4` )
                { `%r4` }
                { ? ( str_contains body_code `%r3` )
                    { `%r3` }
                    { ? ( str_contains body_code `%r2` )
                        { `%r2` }
                        { `%r1` }
                    }
                }
            }
        }
    }
}

// Helper to get first line from string
@ str_first_line s text → s {
    // For now, just return the whole text
    // TODO: Implement proper line splitting
    text
}

// Generate closure body code as string instead of printing directly
@ gen_closure_body_string s captured_vars s env_struct_name i closure_syms s ret_type i cg → s {
    ? == 0 ( count_words captured_vars )
    {
        // No captures - generate appropriate body based on return type
        ? ( seq ret_type `void` )
        {
            // For void functions, just generate an empty body
            ``
        }
        {
            // For non-void functions, return a constant value for now
            : s result ( nurl_cg_reg cg )
            : s code ( nurl_str_cat `  ` result )
            = code ( nurl_str_cat code ` = add i64 42, 0\n` )
            code
        }
    }
    {
        // Has captures - extract from environment and return first one
        : s code ``

        // Cast environment pointer to proper struct type
        : s typed_env ( nurl_cg_reg cg )
        = code ( nurl_str_cat code `  ` )
        = code ( nurl_str_cat code typed_env )
        = code ( nurl_str_cat code ` = bitcast i8* %env to ` )
        = code ( nurl_str_cat code env_struct_name )
        = code ( nurl_str_cat code `*\n` )

        // Extract first captured variable as return value
        : s first_capture ( str_first_word captured_vars )
        : s var_ptr ( nurl_cg_reg cg )
        = code ( nurl_str_cat code `  ` )
        = code ( nurl_str_cat code var_ptr )
        = code ( nurl_str_cat code ` = getelementptr ` )
        = code ( nurl_str_cat code env_struct_name )
        = code ( nurl_str_cat code `, ` )
        = code ( nurl_str_cat code env_struct_name )
        = code ( nurl_str_cat code `* ` )
        = code ( nurl_str_cat code typed_env )
        = code ( nurl_str_cat code `, i64 0, i32 0\n` )  // First field

        : s result ( nurl_cg_reg cg )
        = code ( nurl_str_cat code `  ` )
        = code ( nurl_str_cat code result )
        = code ( nurl_str_cat code ` = load i64, i64* ` )
        = code ( nurl_str_cat code var_ptr )
        = code ( nurl_str_cat code `\n` )

        // Register captured variables in closure symbol table for potential use
        ( nurl_sym_def closure_syms first_capture result )

        code
    }
}

// ── Closure Body Generation ──────────────────────────────────────
// Generate closure body that uses captured variables from environment
@ gen_closure_body_with_captures s captured_vars s env_struct_name i closure_syms i cg → s {
    ? == 0 ( count_words captured_vars )
    {
        // No captures - return a constant value for now
        ( nurl_print `  ` ) : s result ( nurl_cg_reg cg )
        ( nurl_print result ) ( nurl_print ` = add i64 42, 0\n` )  // Simple constant
        result
    }
    {
        // Has captures - extract from environment and return first one

        // Cast environment pointer to proper struct type
        : s typed_env ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print typed_env )
        ( nurl_print ` = bitcast i8* %env to ` ) ( nurl_print env_struct_name )
        ( nurl_print `*\n` )

        // Extract first captured variable as return value
        : s first_capture ( str_first_word captured_vars )
        : s var_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print var_ptr )
        ( nurl_print ` = getelementptr ` ) ( nurl_print env_struct_name )
        ( nurl_print `, ` ) ( nurl_print env_struct_name ) ( nurl_print `* ` )
        ( nurl_print typed_env ) ( nurl_print `, i64 0, i32 0\n` )  // First field

        : s result ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print result )
        ( nurl_print ` = load i64, i64* ` ) ( nurl_print var_ptr ) ( nurl_print `\n` )

        // Register captured variables in closure symbol table for potential use
        // TODO: This could be extended to make all captured vars available
        ( nurl_sym_def closure_syms first_capture result )

        result
    }
}

// ── Try-unwrap \ expr ─────────────────────────────────────────────
// Extracts the success value from a ? T or ! T E expression.
// On failure (tag=0) returns zeroinitializer from the enclosing function.
// Compile errors:
//   T7: \ used on a non-opt/res type
//   T8: error type of \ expression doesn't match enclosing function's error type

@ gen_try_expr i lex i syms i cg → s {
    // '\' is already consumed by gen_backslash_expr
    // Reset NURL call type before evaluating sub-expression
    ( nurl_sym_def syms `__last_nurl_call__` `` )
    : s val ( gen_expr lex syms cg )
    : s vt ( nurl_get_last_type )
    // T7: verify expression is opt or res type (must start with "{ i1, ")
    : b is_opt_res & >= ( nurl_str_len vt ) 6
    ( seq ( nurl_str_slice vt 0 6 ) `{ i1, ` )
    ? ! is_opt_res
    { ( die lex ( nurl_str_cat `try operator \\ used on non-Result type: ` ( llvm_to_nurl vt ) ) ) }
    {}
    // T8: for res_type, verify error type matches enclosing function's error type
    : s call_nurl ( nurl_sym_get syms `__last_nurl_call__` )
    : s fn_nurl ( nurl_sym_get syms `__fn_nurl_ret__` )
    ? & != 0 ( nurl_str_len call_nurl ) != 0 ( nurl_str_len fn_nurl )
    { ? ! ( seq call_nurl fn_nurl )
        {  // extract error type (3rd word, e.g. "! i s" → "s")
            : s call_e ( str_first_word ( str_skip_word ( str_skip_word call_nurl ) ) )
            : s fn_e ( str_first_word ( str_skip_word ( str_skip_word fn_nurl ) ) )
            ? ! ( seq call_e fn_e )
            { ( die lex ( nurl_str_cat4 `try propagation type mismatch — function returns `
                fn_nurl ` but \\ received ` call_nurl ) ) }
            {}
        }
        {}
    }
    {}
    // Extract tag (field 0 → i1)
    : s tag ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print tag )
    ( nurl_print ` = extractvalue ` ) ( nurl_print vt )
    ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, 0\n` )
    // Branch on tag
    : s lok ( nurl_cg_lbl cg `try_ok` )
    : s lfail ( nurl_cg_lbl cg `try_fail` )
    ( nurl_print `  br i1 ` ) ( nurl_print tag )
    ( nurl_print `, label %` ) ( nurl_print lok )
    ( nurl_print `, label %` ) ( nurl_print lfail ) ( emit_dbg_eol )
    // Fail path: propagate the Err/None value, routing through defer chain if active.
    // For res_type: return val (preserves original error payload).
    // For opt_type: return zeroinitializer (None = { false, 0 }).
    ( emit ( nurl_str_cat lfail `:` ) )
    : s fn_rt ( nurl_sym_get syms `__fn_ret_ty__` )
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    // Use the original val if types match (res propagation), else zeroinitializer
    : s fail_val ? ( seq fn_rt vt ) val `zeroinitializer`
    ? != 0 ( nurl_str_len dtop )
    { ? ! ( seq fn_rt `void` )
        { : s rvp ( nurl_sym_get syms `__ret_val__` )
            ( nurl_print `  store ` ) ( nurl_print fn_rt )
            ( nurl_print ` ` ) ( nurl_print fail_val ) ( nurl_print `, ` )
            ( nurl_print fn_rt ) ( nurl_print `* ` ) ( nurl_print rvp ) ( nurl_print `\n` )
        }
        {}
        ( nurl_print `  br label %` ) ( nurl_print dtop ) ( emit_dbg_eol )
    }
    { ? ( seq fn_rt `void` )
        { ( emit_call_term `ret void` ) }
        { ( nurl_print `  ret ` ) ( nurl_print fn_rt )
            ( nurl_print ` ` ) ( nurl_print fail_val ) ( emit_dbg_eol )
        }
    }
    // Ok path: extract inner value (field 1)
    ( emit ( nurl_str_cat lok `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lok )
    = g_did_ret 0
    : s inner_ty ( compound_field_type vt 1 )
    : s res ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print res )
    ( nurl_print ` = extractvalue ` ) ( nurl_print vt )
    ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, 1\n` )
    // For `! T E` whose T is a struct handle (e.g. %String), the payload
    // slot stores the struct's field-0 pointer as i64. Reconstruct the
    // struct here so let_stmt can bind it to the declared type without a
    // separate cast. Only fires for res types (! T E lowers to { i1, i64 }).
    : s call_nurl2 ( nurl_sym_get syms `__last_nurl_call__` )
    : s inner_nurl ``
    : b is_res & >= ( nurl_str_len call_nurl2 ) 2
    ( seq ( nurl_str_slice call_nurl2 0 2 ) `! ` )
    ? is_res
    { = inner_nurl ( str_first_word ( str_skip_word call_nurl2 ) ) } {}
    : s struct_ty ( nurl_sym_get syms inner_nurl )
    // Three reconstruction shapes when inner is i64 and T resolves to %X:
    //   (a) X is a struct whose f0 is a pointer (Vec / String / opaque-handle):
    //       i64 IS f0 — inttoptr + insertvalue at field 0.
    //   (b) X is a struct whose f0 is NOT a pointer (multi-field like ParsedHead,
    //       Pt2, Tagged): i64 is a heap-box %X* — inttoptr + load + nurl_free.
    //   (c) X is a wide enum (max_payloads > 0): same heap-box unbox as (b).
    // Mirrors gen_match's match-arm reconstruction at lines ~1442–1502.
    : b is_struct_handle F
    : b is_heapbox_struct F
    : b is_heapbox_enum F
    : s f0_ty ``
    ? & ( seq inner_ty `i64` ) & != 0 ( nurl_str_len struct_ty ) == ( nurl_str_get struct_ty 0 ) 37
    { : s sname ( nurl_str_slice struct_ty 1 - ( nurl_str_len struct_ty ) 1 )
        : s vlist ( nurl_sym_get syms ( nurl_str_cat sname `__variants` ) )
        ? == 0 ( nurl_str_len vlist )
        { = f0_ty ( nurl_sym_get syms ( nurl_str_cat3 sname `__idx_0` `__type` ) )
            ? & != 0 ( nurl_str_len f0_ty )
            == ( nurl_str_get f0_ty - ( nurl_str_len f0_ty ) 1 ) 42
            { = is_struct_handle T }
            { ? != 0 ( nurl_str_len f0_ty )
                { = is_heapbox_struct T } {} } }
        { : s mp_r ( nurl_sym_get syms ( nurl_str_cat sname `__max_payloads` ) )
            : i mp_rn ? != 0 ( nurl_str_len mp_r ) ( nurl_str_to_int mp_r ) 0
            ? > mp_rn 0 { = is_heapbox_enum T } {} } }
    {}
    ? is_struct_handle
    { : s pcv ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print pcv )
        ( nurl_print ` = inttoptr i64 ` ) ( nurl_print res )
        ( nurl_print ` to ` ) ( nurl_print f0_ty ) ( nurl_print `\n` )
        : s sv ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print sv )
        ( nurl_print ` = insertvalue ` ) ( nurl_print struct_ty )
        ( nurl_print ` undef, ` ) ( nurl_print f0_ty )
        ( nurl_print ` ` ) ( nurl_print pcv ) ( nurl_print `, 0\n` )
        ( nurl_set_last_type struct_ty )
        ^ sv } {}
    ? | is_heapbox_struct is_heapbox_enum
    { : s ubp ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ubp )
        ( nurl_print ` = inttoptr i64 ` ) ( nurl_print res )
        ( nurl_print ` to ` ) ( nurl_print struct_ty ) ( nurl_print `*\n` )
        : s ubv ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ubv )
        ( nurl_print ` = load ` ) ( nurl_print struct_ty )
        ( nurl_print `, ` ) ( nurl_print struct_ty )
        ( nurl_print `* ` ) ( nurl_print ubp ) ( nurl_print `\n` )
        : s ubraw ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ubraw )
        ( nurl_print ` = bitcast ` ) ( nurl_print struct_ty )
        ( nurl_print `* ` ) ( nurl_print ubp ) ( nurl_print ` to i8*\n` )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print ubraw ) ( nurl_print `)` ) ( emit_dbg_eol )
        ( nurl_set_last_type struct_ty )
        ^ ubv } {}
    ( nurl_set_last_type inner_ty )
    res
}

// ── Generic function helpers (Group E) ──────────────────────────────

// str_first_word: first space-delimited word in str.
@ str_first_word s str → s {
    : i slen ( nurl_str_len str )
    : i pos 0
    ~ & < pos slen != ( nurl_str_get str pos ) 32 { = pos + pos 1 }
    ( nurl_str_slice str 0 pos )
}

// str_skip_word: str with first word (and following space) removed.
@ str_skip_word s str → s {
    : i slen ( nurl_str_len str )
    : i pos 0
    ~ & < pos slen != ( nurl_str_get str pos ) 32 { = pos + pos 1 }
    ? & < pos slen == ( nurl_str_get str pos ) 32 { = pos + pos 1 } {}
    ( nurl_str_slice str pos - slen pos )
}

// str_contains_word: true if 'word' appears as a whole word in space-separated 'list'.
@ str_contains_word s list s word → b {
    : s rest list
    ~ != 0 ( nurl_str_len rest ) {
        : s w ( str_first_word rest )
        = rest ( str_skip_word rest )
        ? ( seq w word ) { ^ T } {}
    }
    F
}

// check_exhaustive: compile error if match arms don't cover all enum variants.
// ename: enum name (e.g. "Color")  seen: space-separated matched variant names
// has_wildcard: 1 if a '_' arm was present
@ check_exhaustive i lex s ename s seen i has_wildcard i syms → v {
    ? == has_wildcard 0 {
        : s all ( nurl_sym_get syms ( nurl_str_cat ename `__variants` ) )
        ? != 0 ( nurl_str_len all ) {
            : s rest all
            ~ != 0 ( nurl_str_len rest ) {
                : s vname ( str_first_word rest )
                = rest ( str_skip_word rest )
                ? ! ( str_contains_word seen vname ) {
                    ( die lex ( nurl_str_cat4 `non-exhaustive match on ` ename `, unhandled: ` vname ) )
                } {}
            }
        } {}
    } {}
}

// mangle_type: LLVM type string → valid identifier fragment.
@ mangle_type s lty → s {
    ? ( seq lty `i64` ) ^ `i64`
    ? ( seq lty `double` ) ^ `f64`
    ? ( seq lty `i1` ) ^ `i1`
    ? ( seq lty `i8*` ) ^ `str`
    ? ( seq lty `void` ) ^ `void`
    ? == ( nurl_str_get lty - ( nurl_str_len lty ) 1 ) 42
    ^ ( nurl_str_cat `ptr_` ( mangle_type ( nurl_str_slice lty 0 - ( nurl_str_len lty ) 1 ) ) )
    {}
    ? == ( nurl_str_get lty 0 ) 37
    ^ ( nurl_str_slice lty 1 - ( nurl_str_len lty ) 1 )
    {}
    lty
}

// subst_source: replace whole-word occurrences of 'from' with 'to' in src.
// Words are space-separated tokens as produced by collect_fn_body.
@ subst_source s src s from s to → s {
    : s result ``
    : s rest src
    ~ != 0 ( nurl_str_len rest ) {
        : s word ( str_first_word rest )
        = rest ( str_skip_word rest )
        = result ( nurl_str_cat result
        ( nurl_str_cat ? ( seq word from ) to word ` ` ) )
    }
    result
}

// subst_source_raw: replace whole-identifier occurrences of 'from' with 'to'
// in a raw source string (preserves whitespace, backticks, punctuation).
// Identifier chars: alpha, digit, underscore (95).
@ subst_source_raw s src s from s to → s {
    : s result ``
    : i slen ( nurl_str_len src )
    : i pos 0
    : i word_start 0
    ~ < pos slen {
        : i ch ( nurl_str_get src pos )
        : b is_ident ( __is_ident_char ch )
        ? is_ident
        { = pos + pos 1 }
        { ? > pos word_start
            { : s word ( nurl_str_slice src word_start - pos word_start )
                = result ( nurl_str_cat result ? ( seq word from ) to word )
            }
            {}
            = result ( nurl_str_cat result ( nurl_str_slice src pos 1 ) )
            = pos + pos 1
            = word_start pos
        }
    }
    ? > pos word_start
    { : s word ( nurl_str_slice src word_start - pos word_start )
        = result ( nurl_str_cat result ? ( seq word from ) to word )
    }
    {}
    result
}

// collect_fn_body: collect tokens from current '{' through matching '}'.
// Returns space-separated token text. String literals lack their backtick
// delimiters and will not re-lex correctly; avoid them in generic bodies.
@ collect_fn_body i lex → s {
    : s result ( nurl_str_cat ( nurl_lex_val lex ) ` ` )
    ( nurl_lex_advance lex )
    : i depth 1
    ~ != depth 0 {
        : i tt2 ( nurl_lex_type lex )
        ? == tt2 TT_LBRACE { = depth + depth 1 } {}
        ? == tt2 TT_RBRACE { = depth - depth 1 } {}
        = result ( nurl_str_cat result ( nurl_str_cat ( nurl_lex_val lex ) ` ` ) )
        ( nurl_lex_advance lex )
    }
    result
}

// compute_generic_inout_sink: derive a generic function's `inout` and
// `sink` parameter index sets from its stored template and publish
// them under the GENERIC name in g_fn_inout / g_fn_sink.
//
// A parameter convention is a property of parameter POSITION, not of
// the type arguments, so one computation serves every instantiation.
// A call site looks the sets up by the generic name (see gen_call):
// the mangled-name entry only appears once the deferred instantiation
// is itself compiled, which is too late for the call site that
// triggered it.
//
// parse_type and its helpers emit no IR and trigger no struct
// instantiation — the scan_generic_structs pre-pass owns that — so
// walking the raw template here, tparam tokens (`A` / `T` …) and all,
// is side-effect-free.
@ compute_generic_inout_sink s fname → v {
    : s gsrc ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__gsrc` ) )
    ? != 0 ( nurl_str_len gsrc )
    { // Substitute every type parameter with a concrete primitive (`i`)
      // before parsing. A bare tparam letter such as `T` or `F` lexes
      // as TT_BOOL, which parse_type rejects with `expected type`; the
      // real instantiation path dodges this because emit_one_instantiation
      // substitutes the tparams away first. The substitution is
      // type-irrelevant here — only parameter POSITIONS are read.
        : ~ s probe gsrc
        : ~ s tpr ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
        ~ != 0 ( nurl_str_len tpr )
        { : s tp ( str_first_word tpr )
            = tpr ( str_skip_word tpr )
            = probe ( subst_source probe tp `i` )
        }
        : i lexp ( nurl_lex_new probe `<gsig>` )
        : ~ s ia ``
        : ~ s sa ``
        : ~ i pc 0
        // Walk the parameter region only — stop at `→` (or, defensively,
        // at the body `{` if a malformed template lacks the arrow).
        ~ & & != ( nurl_lex_type lexp ) TT_ARROW != ( nurl_lex_type lexp ) TT_EOF
                != ( nurl_lex_type lexp ) TT_LBRACE
        { : i mk ( parse_param_marker lexp )
            ? == mk 1
            { = ia ? == 0 ( nurl_str_len ia )
                ( nurl_str_int pc )
                ( nurl_str_cat3 ia ` ` ( nurl_str_int pc ) ) }
            {}
            ? == mk 2
            { = sa ? == 0 ( nurl_str_len sa )
                ( nurl_str_int pc )
                ( nurl_str_cat3 sa ` ` ( nurl_str_int pc ) ) }
            {}
            ( parse_type lexp )
            ? ( is_ident_tok ( nurl_lex_type lexp ) )
            { ( nurl_lex_advance lexp ) }
            {}
            = pc + pc 1
        }
        ( nurl_sym_def g_fn_inout fname ia )
        ( nurl_sym_def g_fn_sink fname sa )
    }
    {}
}

// gen_generic_fn_store: record a generic function declaration.
// Called when '[' is seen after the function name in gen_fn_decl.
// Stores source template in g_generic_syms; emits no IR.
@ gen_generic_fn_store i lex i syms s fname → v {
    // DWARF Phase 7: snapshot the declaration line BEFORE consuming
    // template tokens so every later instantiation can attach its
    // !DISubprogram to the original source location, not the line
    // of the synthetic `<generic>` lex emit_one_instantiation uses.
    : i src_line ( nurl_lex_line lex )
    ( nurl_sym_def g_generic_syms
        ( nurl_str_cat fname `__src_line` ) ( nurl_str_int src_line ) )
    ( expect lex TT_LBRACK )
    : s tparams ``
    ~ != ( nurl_lex_type lex ) TT_RBRACK {
        : s tp ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        = tparams ? == 0 ( nurl_str_len tparams ) tp
        ( nurl_str_cat tparams ( nurl_str_cat ` ` tp ) )
    }
    ( expect lex TT_RBRACK )
    // Collect params/return/body tokens until EOF
    : s src ``
    ~ & != ( nurl_lex_type lex ) TT_LBRACE != ( nurl_lex_type lex ) TT_EOF {
        = src ( nurl_str_cat src ( nurl_str_cat ( nurl_lex_val lex ) ` ` ) )
        ( nurl_lex_advance lex )
    }
    ? != ( nurl_lex_type lex ) TT_EOF
    { = src ( nurl_str_cat src ( collect_fn_body lex ) ) }
    {}
    ( nurl_sym_def g_generic_syms ( nurl_str_cat fname `__tparams` ) tparams )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat fname `__gsrc` ) src )
    ( nurl_sym_def syms ( nurl_str_cat fname `__generic` ) `1` )
    // BORROW.md Phase 4: record this generic function's `inout` / `sink`
    // parameter index sets (keyed by the generic name) so a call site
    // can pass `inout` arguments by address and move-mark `sink` ones
    // without waiting for the deferred instantiation to be compiled.
    ( compute_generic_inout_sink fname )
}

// compute_generic_ret_ty: determine return type of a generic instantiation
// without emitting IR. type_args: space-separated raw NURL type tokens.
@ compute_generic_ret_ty s fname s type_args → s {
    : s tparams ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
    : s gsrc ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__gsrc` ) )
    : s subst_src gsrc
    : s tp_rest tparams
    : s ta_rest type_args
    ~ != 0 ( nurl_str_len tp_rest ) {
        : s tp ( str_first_word tp_rest )
        = tp_rest ( str_skip_word tp_rest )
        : s ta ( str_first_word ta_rest )
        = ta_rest ( str_skip_word ta_rest )
        = subst_src ( subst_source subst_src tp ta )
    }
    // subst_src is now: "params → ret_ty { body }"
    // Lex it, skip to →, parse return type.
    : i lex2 ( nurl_lex_new subst_src `<generic_ret>` )
    ~ & != ( nurl_lex_type lex2 ) TT_ARROW != ( nurl_lex_type lex2 ) TT_EOF {
        ( nurl_lex_advance lex2 )
    }
    : s ret_ty `i64`
    ? == ( nurl_lex_type lex2 ) TT_ARROW
    { ( nurl_lex_advance lex2 )
        = ret_ty ( parse_type lex2 )
    }
    {}
    ret_ty
}

// ── Generic struct instantiation ───────────────────────────────────
//
// A generic struct declaration `: Name [T+] { field* }` is stored as a
// template in g_generic_struct_syms during the pre-scan (see
// `scan_generic_structs`). Each distinct use `( Name T1 T2 ... )` in
// type position is materialised here: fields are re-lexed after
// substituting the type params, a `%Name__T1[__T2]` LLVM named type is
// emitted, and field-lookup metadata is stored in `syms`.
//
// This runs during the PRE-SCAN (before any function body is emitted)
// so the resulting type definitions appear at the top of the IR, where
// LLVM's forward-only parser will accept them.
// Heuristic: a single uppercase letter (A–Z), optionally followed by a
// digit, is a generic tparam-like token (the project's tparam naming
// convention — `[A]`, `[K V]`, `[A B]`, `[E]`, `[T1 T2]` …). Returns 1
// if `tok` looks like a tparam, 0 otherwise. Used to skip phantom
// instantiations whose body would substitute `A`/`B`/… into field
// types and reference `%A`/`%B` named types that don't exist (Vec /
// HashMap dodge this by keeping tparams out of field types — Pair
// can't, since its whole point is to hold a tparam-typed value pair).
@ is_tparam_like s tok → b {
    : i n ( nurl_str_len tok )
    ? | < n 1 > n 2 { ^ F } {}
    : i c0 ( nurl_str_get tok 0 )
    ? | < c0 65 > c0 90 { ^ F } {}
    ? == n 1 { ^ T } {}
    : i c1 ( nurl_str_get tok 1 )
    ? & >= c1 48 <= c1 57 { ^ T } { ^ F }
}

@ ensure_struct_instantiated i syms s sname s ta_list → v {
    : s tparams ( nurl_sym_get g_generic_struct_syms ( nurl_str_cat sname `__stparams` ) )
    ? != 0 ( nurl_str_len tparams ) {
        // Skip tparam-only instantiations: they appear inside generic
        // function signatures/bodies (e.g. `pair_first [A B] ( Pair A B )`)
        // where A/B are still abstract. The concrete instantiation emerges
        // when the function is called with concrete type args at parse
        // time and re-enters scan_generic_structs / parse_type_paren.
        : ~ s ta_chk ta_list
        : ~ b skip F
        ~ & != 0 ( nurl_str_len ta_chk ) ! skip {
            : s ta ( str_first_word ta_chk )
            = ta_chk ( str_skip_word ta_chk )
            ? ( is_tparam_like ta ) { = skip T } {}
        }
        ? ! skip {
            // Compute mangled name by walking tparams + ta_list in parallel.
            : s mangled sname
            : ~ s tp_r tparams
            : ~ s ta_r ta_list
            ~ & != 0 ( nurl_str_len tp_r ) != 0 ( nurl_str_len ta_r ) {
                : s tp ( str_first_word tp_r )
                = tp_r ( str_skip_word tp_r )
                : s ta ( str_first_word ta_r )
                = ta_r ( str_skip_word ta_r )
                = mangled ( nurl_str_cat mangled
                ( nurl_str_cat `__` ( mangle_type ( llvm_type ta ) ) ) )
            }
            // Dedupe — each distinct instantiation emitted at most once.
            : s done_key ( nurl_str_cat mangled `__done` )
            ? == 0 ( nurl_str_len ( nurl_sym_get g_struct_inst_syms done_key ) ) {
                ( nurl_sym_def g_struct_inst_syms done_key `1` )
                // Substitute tparam → type-arg in the raw body source.
                : s body ( nurl_sym_get g_generic_struct_syms ( nurl_str_cat sname `__sbody` ) )
                : ~ s subst body
                : ~ s tp_r2 tparams
                : ~ s ta_r2 ta_list
                ~ & != 0 ( nurl_str_len tp_r2 ) != 0 ( nurl_str_len ta_r2 ) {
                    : s tp ( str_first_word tp_r2 )
                    = tp_r2 ( str_skip_word tp_r2 )
                    : s ta ( str_first_word ta_r2 )
                    = ta_r2 ( str_skip_word ta_r2 )
                    = subst ( subst_source_raw subst tp ta )
                }
                // Recursively materialise nested generic-struct refs in
                // the substituted body — the outer typedef line about to
                // be emitted must reference fully-sized inner types, not
                // opaque forward decls. (LLVM allows forward `%Name` refs
                // but won't size a struct whose layout depends on an
                // unresolved-at-parse-time element type, which breaks any
                // downstream `getelementptr` of the outer struct.) The
                // `__done` dedup marker for `mangled` was set above, so
                // a self-referential struct won't recurse infinitely.
                : i lex_inner ( nurl_lex_new subst ( nurl_str_cat `<inst-rescan:` ( nurl_str_cat mangled `>` ) ) )
                ( scan_generic_structs lex_inner syms )
                // Re-lex, skip outer '{', parse each field via parse_type + IDENT.
                : i lex2 ( nurl_lex_new subst ( nurl_str_cat `<inst:` ( nurl_str_cat mangled `>` ) ) )
                ? == ( nurl_lex_type lex2 ) TT_LBRACE { ( nurl_lex_advance lex2 ) } {}
                ( nurl_print `%` ) ( nurl_print mangled ) ( nurl_print ` = type { ` )
                : ~ i first 1
                : ~ i fidx 0
                ~ & != ( nurl_lex_type lex2 ) TT_RBRACE != ( nurl_lex_type lex2 ) TT_EOF {
                    : s flt ( parse_type lex2 )
                    ? ( is_ident_tok ( nurl_lex_type lex2 ) )
                    { : s fname ( nurl_lex_val lex2 )
                        ( nurl_lex_advance lex2 )
                        ( nurl_sym_def syms
                        ( nurl_str_cat mangled ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) )
                        ( nurl_str_int fidx ) )
                        ( nurl_sym_def syms
                        ( nurl_str_cat mangled ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) )
                        flt )
                        ( nurl_sym_def syms
                        ( nurl_str_cat3 mangled `__idx_` ( nurl_str_cat ( nurl_str_int fidx ) `__type` ) )
                        flt )
                        ( nurl_sym_def syms
                        ( nurl_str_cat3 mangled `__idx_` ( nurl_str_cat ( nurl_str_int fidx ) `__name` ) )
                        fname )
                    }
                    {}
                    ? != first 0
                    { ( nurl_print flt ) = first 0 }
                    { ( nurl_print `, ` ) ( nurl_print flt ) }
                    = fidx + fidx 1
                }
                ( nurl_print ` }\n\n` )
                ( nurl_sym_def syms mangled ( nurl_str_cat `%` mangled ) )
                ( nurl_sym_def syms ( nurl_str_cat mangled `__is_type` ) `1` )
                ( nurl_sym_def syms ( nurl_str_cat mangled `__field_count` ) ( nurl_str_int fidx ) )
            } {}
        } {}
    } {}
}

// defer_instantiation: queue a generic instantiation for emission after
// the calling function's closing '}'. Returns the mangled name.
@ defer_instantiation s fname s mangled s type_args i syms → v {
    : s ret_ty ( compute_generic_ret_ty fname type_args )
    ( nurl_sym_def syms mangled ret_ty )
    : s cnt_s ( nurl_sym_get g_generic_syms `__deferred_count__` )
    : i n ( nurl_str_to_int cnt_s )
    ( nurl_sym_def g_generic_syms `__deferred_count__` ( nurl_str_int + n 1 ) )
    : s base ( nurl_str_cat `__def` ( nurl_str_int n ) )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat base `_fn` ) fname )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat base `_mn` ) mangled )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat base `_ta` ) type_args )
}

// emit_str_globals: emit global constants for string literals [base..top).
@ emit_str_globals i base i top → v {
    : i sg g_str_syms
    : i k base
    ~ < k top {
        : s kstr ( nurl_str_int k )
        : s enc ( nurl_sym_get sg ( nurl_str_cat `__enc_` kstr ) )
        : s len ( nurl_sym_get sg ( nurl_str_cat `__len_` kstr ) )
        ( nurl_print `@.str.` ) ( nurl_print kstr )
        ( nurl_print ` = private unnamed_addr constant [` )
        ( nurl_print len ) ( nurl_print ` x i8] c"` )
        ( nurl_print enc ) ( nurl_print `\00"\n` )
        = k + k 1
    }
}

// emit_closure_globals: emit only NEW deferred closure definitions since last call
@ emit_closure_globals → v {
    // Emit new closure function definitions (from watermark to current)
    : i defs_syms g_closure_defs
    : i idx g_closure_emit_base
    ~ < idx g_func_count {
        : s funcdef ( nurl_sym_get defs_syms ( nurl_str_int idx ) )
        ? != 0 ( nurl_str_len funcdef )
        { ( nurl_print funcdef ) }
        {}
        = idx + idx 1
    }
    = g_closure_emit_base g_func_count
}

// ── Function declaration @ name params → ret { body } ─────────────

@ gen_fn_decl i lex i syms i cg → v {
    ( nurl_lex_advance lex )
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s fname ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        // Grammar v2.0: re-record (idempotent) the source-file + public
        // flag during the parse_program pass. scan_fn_sigs has already
        // populated g_vis_syms; calling here ensures g_pending_pub is
        // cleared so a stray `pub` doesn't leak to a later decl.
        ( vis_record_fn fname ( vis_take_pending_pub ) )
        // Generic declaration: store template, emit no IR now.
        // Disambiguation: [T] / [K V] are generic, [ T name / [i x are slice param.
        // Generic param list ends with ']' shortly. Slice never has ']' in its type.
        //   [ X ]            (peek2=RBRACK)              → generic 1-param
        //   [ X Y ]          (peek2=name, peek3=RBRACK)  → generic 2-param
        //   anything else                                → slice param
        ? == ( nurl_lex_type lex ) TT_LBRACK
        { : i p1 ( nurl_lex_peek_type lex )
            : i p2 ( nurl_lex_peek2_type lex )
            : i p3 ( nurl_lex_peek3_type lex )
            : b is_name1 | == p1 TT_IDENT == p1 TT_BOOL
            : b is_name2 | == p2 TT_IDENT == p2 TT_BOOL
            : b is_name3 | == p3 TT_IDENT == p3 TT_BOOL
            : b gen1 & is_name1 == p2 TT_RBRACK
            : b gen2 & & is_name1 is_name2 == p3 TT_RBRACK
            // 3-param generic `[ A B C ]` needs peek4 because a slice param
            // followed by an IDENT-typed param (e.g. `[ i xs Name y`) also
            // shows three consecutive IDENTs after '['. Only `]` at position 4
            // disambiguates.
            : i p4 ? & & is_name1 is_name2 is_name3 ( nurl_lex_peek4_type lex ) 0
            : b gen3 & & & is_name1 is_name2 is_name3 == p4 TT_RBRACK
            ? | | gen1 gen2 gen3
            { ( gen_generic_fn_store lex syms fname ) }
            { ( gen_fn_decl_concrete fname lex syms cg ) }
        }
        { ( gen_fn_decl_concrete fname lex syms cg ) }
    }
    { ( die lex `expected function name after @` ) }
}

@ gen_fn_decl_concrete s fname i lex i syms i cg → v {
    ( nurl_cg_reset cg )
    // Borrow checker: start a fresh per-function statement list.
    ( bck_fn_begin )
    // Snapshot the lex position for DWARF DISubprogram.line / scopeLine
    // before we consume any tokens — by the time we reach the `define`
    // emit, the lexer has advanced past the param list and `→`, so a
    // later snapshot would point inside the body instead of the header.
    // For generic instantiations, emit_one_instantiation pre-seeds
    // `g_dbg_override_line` with the ORIGINAL generic-decl source line
    // so the mono's subprogram points there instead of the synthetic
    // `<generic>:1` of the inflated source.
    : i fn_src_line ? != g_dbg_enabled 0
        ? != g_dbg_override_line 0 g_dbg_override_line ( nurl_lex_line lex )
        0
    ( nurl_sym_push syms )
    ( nurl_sym_def syms `__owned_slices__` `` )
    ( nurl_sym_def syms `__last_ident_name__` `` )
    ( nurl_sym_def syms `__fn_ret_owned__` `` )
    ? != 0 g_auto_drop_strings
    { ( nurl_sym_def syms `__owned_strings__` `` )
        ( nurl_sym_def syms `__owned_struct_fields__` `` )
        ( nurl_sym_def syms `__user_drops__` `` )
        ( nurl_sym_def syms `__fn_ret_str_owned__` `` )
    }
    {}
    : s params_str ``
    : i pct 0
    // BORROW.md Phase 4: accumulate the 0-based indices of `inout`
    // (and `sink`) parameters as gen_fn_param reports them, then
    // publish the sets to g_fn_inout / g_fn_sink so call sites can
    // pass `inout` arguments by address and move-mark `sink` ones.
    : ~ s inout_acc ``
    : ~ s sink_acc ``
    // Reset the param roster before parsing — gen_fn_param appends
    // (name,type) pairs as `name\ttype|name\ttype|…` so
    // __alloca_struct_params can iterate them after `entry:` is
    // emitted and back struct-typed params with alloca slots.
    ( nurl_sym_def syms `__fn_params__` `` )
    // Also reset the space-separated name-only roster consulted by
    // gen_let_or_struct's shadow check (docs/GOTCHAS.md §3). Closures
    // shadow this key inside their own body via the `nurl_sym_push`
    // / `nurl_sym_pop` scope, so a `:` inside a closure body checks
    // against the closure's params — not the enclosing function's.
    ( nurl_sym_def syms `__fn_param_names__` `` )
    // Guard against EOF too: without this, a malformed header that
    // never produces TT_ARROW (e.g. ASCII `->` instead of `→`) hangs
    // the compiler in an infinite loop, because gen_fn_param on EOF
    // cannot advance past the end.
    ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF {
        ( gen_fn_param lex syms params_str pct )
        ? ( seq ( nurl_sym_get syms `__last_param_inout__` ) `1` )
        { = inout_acc ? == 0 ( nurl_str_len inout_acc )
            ( nurl_str_int pct )
            ( nurl_str_cat3 inout_acc ` ` ( nurl_str_int pct ) ) }
        {}
        ? ( seq ( nurl_sym_get syms `__last_param_sink__` ) `1` )
        { = sink_acc ? == 0 ( nurl_str_len sink_acc )
            ( nurl_str_int pct )
            ( nurl_str_cat3 sink_acc ` ` ( nurl_str_int pct ) ) }
        {}
        = params_str ( nurl_get_last_type )
        = pct + pct 1
    }
    // BORROW.md Phase 4: publish this function's inout / sink
    // parameter sets (empty for an ordinary function — harmless,
    // gen_call treats an empty / absent entry the same).
    ( nurl_sym_def g_fn_inout fname inout_acc )
    ( nurl_sym_def g_fn_sink fname sink_acc )
    ( expect lex TT_ARROW )
    // Reset last_res_nurl so we can detect if parse_type_res was called for this return type
    ( nurl_sym_def g_res_type_syms `__last_res_nurl__` `` )
    : s ret_ty ( parse_type lex )
    : s nurl_ret ( nurl_sym_get g_res_type_syms `__last_res_nurl__` )
    ( nurl_sym_def syms fname ret_ty )
    ( nurl_sym_def syms `__fn_ret_ty__` ret_ty )
    // Store NURL return type for try-propagation type checking
    ( nurl_sym_def syms `__fn_nurl_ret__` nurl_ret )
    ( nurl_sym_def syms ( nurl_str_cat fname `__nurl_ret` ) nurl_ret )
    : s lname ? ( seq fname `main` ) `_nurl_main` fname
    ( nurl_print `define ` ) ( nurl_print ret_ty )
    ( nurl_print ` @` ) ( nurl_print lname )
    ( nurl_print `(` ) ( nurl_print params_str ) ( nurl_print `)` )
    // DWARF: attach `!dbg !N` to the define line (referencing this fn's
    // !DISubprogram) and seed g_dbg_current_loc with a DILocation at
    // fn-entry. emit_dbg_eol then attaches `!dbg` to every call/ret/br
    // inside the body. Both globals reset to 0 after the closing `}`.
    ? != g_dbg_enabled 0
    { : i sp_id ( dbg_emit_subprogram lname fn_src_line )
        : i loc_id ( dbg_emit_location fn_src_line 1 sp_id )
        = g_dbg_current_subprogram sp_id
        = g_dbg_current_loc loc_id
        ( nurl_print ` !dbg !` ) ( nurl_print ( nurl_str_int sp_id ) ) }
    {}
    ( nurl_print ` {\n` )
    ( emit `entry:` )
    ( nurl_sym_def syms `__cur_lbl__` `entry` )
    = g_did_ret 0
    = g_defer_count 0
    // Back struct-typed params with entry-block alloca + store so
    // `= . p field val` inside the body works (gen_field_store needs
    // a pointer base via `<obj>__ptr`). See `__alloca_struct_params`
    // for the predicate (multi-field named struct, not enum).
    ( __alloca_struct_params syms cg )
    : s fn_cleanup ( nurl_cg_lbl cg `fn_cleanup` )
    ( nurl_sym_def syms `__fn_cleanup__` fn_cleanup )
    ( nurl_sym_def syms `__defer_top__` `` )
    // Pre-allocate return-value slot for defer routing (non-void functions).
    // Unused if no defers are registered; optimiser removes it.
    : s ret_val_ptr ``
    ? ! ( seq ret_ty `void` )
    { : s p ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print p )
        ( nurl_print ` = alloca ` ) ( nurl_print ret_ty ) ( nurl_print `\n` )
        ( nurl_sym_def syms `__ret_val__` p )
        = ret_val_ptr p
    }
    {}
    : i base_str g_str_idx
    : s last ( gen_block_ret lex syms cg )
    // Implicit return — route through defer chain if defers are active
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    // Ownership transfer: if ret type is a slice AND the last expression
    // resolved to a simple identifier load, that binding escapes.
    : s ret_ident ( nurl_sym_get syms `__last_ident_name__` )
    : s skip ? & ( mem_is_slice_ty ret_ty ) ( str_contains_word ( nurl_sym_get syms `__owned_slices__` ) ret_ident )
    ret_ident
    ``
    // Phase 2B: compute skip_str_ptr — the alloca ptr of the owned string
    // being returned (if any), so mem_drop_owned_strings doesn't free it.
    : s skip_str_ptr ``
    : s skip_user_ptr ``
    ? != 0 g_auto_drop_strings
    { : s rid_ptr ( nurl_sym_get syms ( nurl_str_cat ret_ident `__ptr` ) )
        = skip_str_ptr ? & ( seq ret_ty `i8*` ) ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) rid_ptr )
        rid_ptr
        ``
        ? != 0 ( nurl_str_len skip_str_ptr )
        { ( nurl_sym_def syms `__fn_ret_str_owned__` `1` ) }
        {}
        = skip_user_ptr ? ( str_contains_word ( nurl_sym_get syms `__user_drops__` ) rid_ptr )
        rid_ptr
        ``
    }
    {}
    ? != 0 ( nurl_str_len skip )
    { ( nurl_sym_def syms `__fn_ret_owned__` `1` ) }
    {}
    ? ( seq ret_ty `void` )
    { ? == g_did_ret 0
        { ? != 0 ( nurl_str_len dtop )
            { ( nurl_print `  br label %` ) ( nurl_print dtop ) ( emit_dbg_eol ) }
            { ( mem_drop_owned syms cg skip )
                ? != 0 g_auto_drop_strings
                { ( mem_drop_owned_strings syms cg skip_str_ptr )
                    ( mem_drop_owned_struct_fields syms cg )
                    ( mem_drop_user_drops syms cg skip_user_ptr )
                }
                {}
                ( emit_call_term `ret void` ) }
        }
        {}
    }
    { ? == g_did_ret 0
        { ? != 0 ( nurl_str_len dtop )
            { ( nurl_print `  store ` ) ( nurl_print ret_ty ) ( nurl_print ` ` )
                ( nurl_print last ) ( nurl_print `, ` ) ( nurl_print ret_ty )
                ( nurl_print `* ` ) ( nurl_print ret_val_ptr ) ( nurl_print `\n` )
                ( nurl_print `  br label %` ) ( nurl_print dtop ) ( emit_dbg_eol )
            }
            { ( mem_drop_owned syms cg skip )
                ? != 0 g_auto_drop_strings
                { ( mem_drop_owned_strings syms cg skip_str_ptr )
                    ( mem_drop_owned_struct_fields syms cg )
                    ( mem_drop_user_drops syms cg skip_user_ptr )
                }
                {}
                ( nurl_print `  ret ` ) ( nurl_print ret_ty )
                ( nurl_print ` ` ) ( nurl_print last ) ( emit_dbg_eol ) }
        }
        {}
    }
    // Emit cleanup block only when defers are present
    ? != 0 ( nurl_str_len dtop )
    { ( emit ( nurl_str_cat fn_cleanup `:` ) )
        ? ! ( seq ret_ty `void` )
        { : s rv ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print rv )
            ( nurl_print ` = load ` ) ( nurl_print ret_ty )
            ( nurl_print `, ` ) ( nurl_print ret_ty )
            ( nurl_print `* ` ) ( nurl_print ret_val_ptr ) ( nurl_print `\n` )
            ( nurl_print `  ret ` ) ( nurl_print ret_ty )
            ( nurl_print ` ` ) ( nurl_print rv ) ( emit_dbg_eol )
        }
        { ( emit_call_term `ret void` ) }
    }
    {}
    ( emit `}` ) ( emit `` )
    // Clear DWARF state — subsequent module-scope code (string globals,
    // closure defs, the next function's metadata) must not inherit
    // this function's DILocation, or its calls would attach `!dbg !N`
    // referencing a stale scope. Reset to 0; emit_dbg_eol then degrades
    // to a plain `\n` until the next function sets it again.
    = g_dbg_current_subprogram 0
    = g_dbg_current_loc 0
    ( emit_str_globals base_str g_str_idx )
    ( emit_closure_globals )
    // Borrow checker (BORROW.md): the function body is fully parsed —
    // run the analysis pass before the scope is popped. No-op unless
    // --borrowck is set; never emits IR.
    ( borrowck_fn_end lex syms fname )
    // Snapshot owned-return flags BEFORE pop: nurl_sym_get returns a pointer
    // into the current scope's entry, which nurl_sym_pop then frees.
    : i fn_ret_owned_flag ? != 0 ( nurl_str_len ( nurl_sym_get syms `__fn_ret_owned__` ) ) 1 0
    : i fn_ret_str_owned_flag ? != 0 g_auto_drop_strings
    ? != 0 ( nurl_str_len ( nurl_sym_get syms `__fn_ret_str_owned__` ) ) 1 0
    0
    ( nurl_sym_pop syms )
    ( nurl_sym_def syms fname ret_ty )
    // Re-store NURL ret type in outer scope (inner scope was just popped)
    ( nurl_sym_def syms ( nurl_str_cat fname `__nurl_ret` ) nurl_ret )
    // Persist "returns owned X" flag: "1" = slice, "str" = string.
    // A function returns at most one kind of owned value, so one sideband
    // key suffices. When Phase 2B is off `fn_ret_str_owned_flag` is always 0.
    ? != 0 fn_ret_str_owned_flag
    { ( nurl_sym_def syms ( nurl_str_cat fname `__ret_owned` ) `str` ) }
    { ? != 0 fn_ret_owned_flag
        { ( nurl_sym_def syms ( nurl_str_cat fname `__ret_owned` ) `1` ) }
        {}
    }
    ? ( seq fname `main` ) ( emit_main_wrapper ret_ty ) {}
}

// Parse one parameter; return accumulated params_str via nurl_set_last_type.
// parse_type handles base types, pointer types, and all compound types.
// Consume an optional parameter-convention marker (BORROW.md Phase 4,
// Option B — mutable value semantics). Returns the convention:
//   0 — default / explicit `in` : immutable borrow, by value (today's
//       behaviour — a parameter is immutable unless mutated through a
//       handle's shared buffer)
//   1 — `inout`                 : exclusive mutable borrow — the
//       callee mutates the caller's value in place
//   2 — `sink`                  : the callee consumes (moves) the value
// The markers are *contextual keywords*: recognised only as the first
// token of a parameter, where no type can legally be named
// `in`/`inout`/`sink`. A parameter NAMED `in`/`inout`/`sink` is still
// fine — the marker check looks only at a parameter's leading token.
@ parse_param_marker i lex → i {
    ? ! ( is_ident_tok ( nurl_lex_type lex ) ) { ^ 0 } {}
    : s v ( nurl_lex_val lex )
    ? ( seq v `inout` ) { ( nurl_lex_advance lex ) ^ 1 } {}
    ? ( seq v `sink` ) { ( nurl_lex_advance lex ) ^ 2 } {}
    ? ( seq v `in` ) { ( nurl_lex_advance lex ) ^ 0 } {}
    0
}

@ gen_fn_param i lex i syms s cur_params i pct → v {
    ( nurl_sym_def g_res_type_syms `__last_nurl_type__` `` )
    // BORROW.md Phase 4: `__last_param_inout__` / `__last_param_sink__`
    // report back to gen_fn_decl_concrete which convention this
    // parameter used, so it can record the function's inout / sink
    // index sets in g_fn_inout / g_fn_sink.
    ( nurl_sym_def syms `__last_param_inout__` `` )
    ( nurl_sym_def syms `__last_param_sink__` `` )
    // BORROW.md Phase 4: optional in/inout/sink convention marker.
    // A `sink` parameter consumes its argument; codegen-wise it is an
    // ordinary by-value parameter (the convention is enforced at the
    // call site — gen_call move-marks the argument), so it needs no
    // special handling here beyond the side-channel below.
    : i pconv ( parse_param_marker lex )
    : s lt ( parse_type lex )
    : s p_nurl_type ( nurl_sym_get g_res_type_syms `__last_nurl_type__` )
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s pname ( nurl_lex_val lex )
        // Reject parameter names that collide with LLVM reserved basic-
        // block labels. Every NURL function emits an `entry:` block as
        // its first label; a param named `entry` then collides at
        // `%entry` lookup time and the bootstrap compiler emits a
        // cryptic "unable to create block named 'entry'" LLVM error
        // far from the source. Close GOTCHAS.md item 3.
        ? ( seq pname `entry` )
        { ( die lex `parameter name 'entry' collides with LLVM's reserved entry: block label. Rename (e.g. 'ent', 'tab_entry'). See docs/GOTCHAS.md item 8.` ) }
        {}
        // BORROW.md Phase 4: `inout` is a parameter-convention keyword;
        // banning it as a parameter NAME keeps the scan_fn_sigs
        // forward-reference check (`<fname>__has_inout`) exact.
        ? ( seq pname `inout` )
        { ( die lex `parameter name 'inout' is a reserved convention keyword (BORROW.md Phase 4) - rename it` ) }
        {}
        ( nurl_lex_advance lex )
        ( nurl_sym_def syms pname lt )
        // Mark parameter as immutable by design
        ( nurl_sym_def syms ( nurl_str_cat pname `__param` ) `1` )
        // BORROW.md Phase 4: an `inout` parameter is an exclusive
        // mutable borrow. It lowers to exactly today's `*T`-by-address
        // mechanism: the LLVM parameter is `<T>* %name`, and the body
        // sees it as a mutable place whose backing pointer (`__ptr`) is
        // the incoming pointer argument itself — no local alloca, so
        // reads and `=` writes land on the caller's storage. This is
        // the same shape as a by-pointer closure capture. The caller
        // passes the argument binding's address (see gen_call). For a
        // borrow-clean program that uses no `inout`, nothing here runs
        // and emitted IR is byte-identical.
        ? == pconv 1
        { ( nurl_sym_def syms ( nurl_str_cat pname `__mutable` ) `1` )
            ( nurl_sym_def syms ( nurl_str_cat pname `__ptr` ) ( nurl_str_cat `%` pname ) )
            ( nurl_sym_def syms ( nurl_str_cat pname `__inout` ) `1` )
            ( nurl_sym_def syms `__last_param_inout__` `1` ) }
        {}
        // A `sink` parameter is an ordinary by-value parameter here;
        // only the side-channel is set so gen_fn_decl_concrete records
        // the index. The consume is enforced at the call site.
        ? == pconv 2
        { ( nurl_sym_def syms `__last_param_sink__` `1` ) }
        {}
        // Track NURL source type + signedness for fixed-width int/float
        // parameters (consulted at cast / store sites).
        ? != 0 ( nurl_str_len p_nurl_type )
        { ( nurl_sym_def syms ( nurl_str_cat pname `__nurl_type` ) p_nurl_type )
            ? ( nurl_type_is_unsigned p_nurl_type )
            { ( nurl_sym_def syms ( nurl_str_cat pname `__unsigned` ) `1` ) }
            {} }
        {}
        // Append this param's name + LLVM type to the function's param
        // roster so gen_fn_decl_concrete can later (post-`entry:`) emit
        // alloca + store for struct params, enabling `= . p field val`
        // inside the body. Format: space-separated `name type name type ...`
        // since param types may contain spaces (`{ i1, i64 }`)? No —
        // closures decompose to `{ R(i8*…)*, i8* }` which DOES contain
        // commas + spaces. Use a pipe separator between (name,type) pairs.
        // An `inout` parameter is skipped — its `__ptr` is already the
        // incoming pointer, so __alloca_struct_params must NOT alloca it.
        ? == pconv 1 {} {
            : s roster ( nurl_sym_get syms `__fn_params__` )
            : s pair ( nurl_str_cat3 pname `\t` lt )
            : s next ? == 0 ( nurl_str_len roster ) pair ( nurl_str_cat3 roster `|` pair )
            ( nurl_sym_def syms `__fn_params__` next )
        }
        // Mirror the param name into the name-only roster used by
        // gen_let_or_struct's shadow check. Space-separated; matches
        // `str_contains_word` semantics.
        : s name_roster ( nurl_sym_get syms `__fn_param_names__` )
        : s name_next ? == 0 ( nurl_str_len name_roster ) pname ( nurl_str_cat3 name_roster ` ` pname )
        ( nurl_sym_def syms `__fn_param_names__` name_next )
        // An `inout` parameter's LLVM type is a pointer to T.
        : s entry ? == pconv 1
            ( nurl_str_cat4 lt `* %` pname `` )
            ( nurl_str_cat3 lt ` %` pname )
        ? == pct 0
        ( nurl_set_last_type entry )
        ( nurl_set_last_type ( nurl_str_cat3 cur_params `, ` entry ) )
    }
    { ( die lex `expected parameter name after type` ) }
}

// Iterate __fn_params__ at function entry and emit alloca + store for
// every parameter whose LLVM type is a multi-field named struct
// (`%T` with `__idx_1__type` registered and not an enum). The store
// gives the parameter a backing pointer so `= . p field val` (handled
// by gen_field_store's "struct by value" branch) can GEP through it
// instead of producing an invalid IR with an empty GEP base.
//
// Single-field handle structs (%String, %Vec) are skipped — their
// f0 IS already a pointer, and the mutations the body would emit
// land through that pointer rather than through this alloca.
//
// Enums are skipped — bare-variant assignment on a parameter would
// reassign the whole binding, which is currently forbidden anyway
// (`__param=1` triggers the "cannot assign to immutable parameter"
// error in gen_assign), and field-on-enum syntax isn't valid.
//
// Closes the field-mutation half of docs/GOTCHAS.md §2 for the
// function-parameter case (previously the closure capture half was
// closed by the by-pointer capture fix earlier today).
@ __alloca_struct_params i syms i cg → v {
    : s roster ( nurl_sym_get syms `__fn_params__` )
    ~ != 0 ( nurl_str_len roster ) {
        // Take one (name,type) pair: everything up to the next '|'.
        : i rlen ( nurl_str_len roster )
        : i pi 0
        ~ & < pi rlen != ( nurl_str_get roster pi ) 124 { = pi + pi 1 }
        : s pair ( nurl_str_slice roster 0 pi )
        = roster ? < pi rlen ( nurl_str_slice roster + pi 1 - rlen - pi 1 ) ``
        // Split pair on '\t'.
        : i plen ( nurl_str_len pair )
        : i ti 0
        ~ & < ti plen != ( nurl_str_get pair ti ) 9 { = ti + ti 1 }
        : s pname ( nurl_str_slice pair 0 ti )
        : s ptype ? < ti plen ( nurl_str_slice pair + ti 1 - plen - ti 1 ) ``
        // Multi-field named struct test: starts with '%', __idx_1__type set,
        // not an enum.
        ? & != 0 ( nurl_str_len ptype ) == ( nurl_str_get ptype 0 ) 37
        { : s tname ( nurl_str_slice ptype 1 - ( nurl_str_len ptype ) 1 )
            : s vlist ( nurl_sym_get syms ( nurl_str_cat tname `__variants` ) )
            ? == 0 ( nurl_str_len vlist )
            { : s f1 ( nurl_sym_get syms ( nurl_str_cat3 tname `__idx_1` `__type` ) )
                ? != 0 ( nurl_str_len f1 )
                { : s pp ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print pp )
                    ( nurl_print ` = alloca ` ) ( nurl_print ptype ) ( nurl_print `\n` )
                    ( nurl_print `  store ` ) ( nurl_print ptype ) ( nurl_print ` %` )
                    ( nurl_print pname ) ( nurl_print `, ` ) ( nurl_print ptype )
                    ( nurl_print `* ` ) ( nurl_print pp ) ( nurl_print `\n` )
                    ( nurl_sym_def syms ( nurl_str_cat pname `__ptr` ) pp ) }
                {} }
            {} }
        {}
    }
    ( nurl_sym_def syms `__fn_params__` `` )
}

@ emit_main_wrapper s ret_ty → v {
    ( emit `define i32 @main(i32 %argc, i8** %argv) {` )
    ( emit `entry:` )
    ( emiti `call void @nurl_init(i32 %argc, i8** %argv)` )
    ? ( seq ret_ty `void` )
    { ( emiti `call void @_nurl_main()` ) ( emiti `ret i32 0` ) }
    { ( emiti `%_ret = call i64 @_nurl_main()` )
        ( emiti `%_exit = trunc i64 %_ret to i32` )
        ( emiti `ret i32 %_exit` ) }
    ( emit `}` ) ( emit `` )
}

// ── Top-level constant / struct declaration ── : ... ──────────────

@ gen_const_or_struct i lex i syms → v {
    ( nurl_lex_advance lex )
    // Check for optional ~ (mutable) token for globals
    : b is_global_mutable == ( nurl_lex_type lex ) TT_TILDE
    ? is_global_mutable { ( nurl_lex_advance lex ) } {}
    ? == ( nurl_lex_type lex ) TT_PIPE
    { ( gen_enum_decl lex syms ) }
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s ty_tok ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        // Generic struct declaration `: Name [T+] { ... }`: scan_generic_structs
        // already stored the template and emitted every instantiated type.
        // Here we just consume the [tparams] + body so parse_program advances.
        ? == ( nurl_lex_type lex ) TT_LBRACK
        { ( nurl_lex_advance lex )
            ~ & != ( nurl_lex_type lex ) TT_RBRACK != ( nurl_lex_type lex ) TT_EOF
            { ( nurl_lex_advance lex ) }
            ? == ( nurl_lex_type lex ) TT_RBRACK { ( nurl_lex_advance lex ) } {}
            ( skip_balanced lex )
        }
        { ? == ( nurl_lex_type lex ) TT_LBRACE
            ( gen_struct_decl ty_tok lex syms )
            ( gen_const_decl ty_tok is_global_mutable lex syms )
        }
    }
    { ( nurl_lex_advance lex ) }
}

@ gen_struct_decl s sname i lex i syms → v {
    ( nurl_lex_advance lex )
    // Grammar v2.0+: consume the parse-program-staged `pub` flag and
    // record per-file origin / public marker so cross-file references
    // can be checked at parse_type_base / gen_agg_lit time.
    ( vis_record_type sname ( vis_take_pending_pub ) )
    ( nurl_print `%` ) ( nurl_print sname ) ( nurl_print ` = type { ` )
    : i first 1
    : i fidx 0
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        : s flt ( parse_type lex )
        ? ( is_ident_tok ( nurl_lex_type lex ) )
        { : s fname ( nurl_lex_val lex )
            ( nurl_lex_advance lex )
            // Store field metadata in symbol table:
            //   sname__fname__idx   → stringified index
            //   sname__fname__type  → LLVM type string (by name)
            //   sname__idx_N__type  → LLVM type string (by index, used by
            //                          Phase 2C struct-field drop for slices)
            //   sname__idx_N__name  → field name (used by DWARF Phase 6
            //                          composite-type emission to label
            //                          each !DIDerivedType DW_TAG_member)
            ( nurl_sym_def syms
            ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) )
            ( nurl_str_int fidx ) )
            ( nurl_sym_def syms
            ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) )
            flt )
            ( nurl_sym_def syms
            ( nurl_str_cat3 sname `__idx_` ( nurl_str_cat ( nurl_str_int fidx ) `__type` ) )
            flt )
            ( nurl_sym_def syms
            ( nurl_str_cat3 sname `__idx_` ( nurl_str_cat ( nurl_str_int fidx ) `__name` ) )
            fname )
        }
        {}
        ? != first 0
        { ( nurl_print flt ) = first 0 }
        { ( nurl_print `, ` ) ( nurl_print flt ) }
        = fidx + fidx 1
    }
    ( nurl_lex_advance lex )
    ( nurl_print ` }\n\n` )
    // Register struct name so it is recognised as a named type in enum payloads etc.
    ( nurl_sym_def syms sname ( nurl_str_cat `%` sname ) )
    ( nurl_sym_def syms ( nurl_str_cat sname `__is_type` ) `1` )
    ( nurl_sym_def syms ( nurl_str_cat sname `__field_count` ) ( nurl_str_int fidx ) )
}

@ gen_const_decl s ty_tok b is_mutable i lex i syms → v {
    : s lt ( llvm_type ty_tok )
    // Grammar v2.0+: consume staged `pub` flag, record origin + public
    // marker. Read BEFORE the cname is known so a stray pub on a
    // malformed const decl still clears.
    : b const_pub ( vis_take_pending_pub )
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s cname ( nurl_lex_val lex )
        ( vis_record_const cname const_pub )
        ( nurl_lex_advance lex )
        : i tt ( nurl_lex_type lex )
        ? == tt TT_INT
        { : i n ( nurl_lex_inum lex )
            ( nurl_lex_advance lex )
            ( nurl_print `@` ) ( nurl_print cname )
            ( nurl_print ` = global ` ) ( nurl_print lt ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n\n` )
            ( nurl_sym_def syms cname lt )
            ( nurl_sym_def syms ( nurl_str_cat cname `__global` ) `1` )
            ? is_mutable
            { ( nurl_sym_def syms ( nurl_str_cat cname `__mutable` ) `1` ) }
            {}
            // TEMPORARILY DISABLED: ( nurl_sym_def syms ( nurl_str_cat cname `__newsyntax` ) `1` )
        }
        ? == tt TT_FLOAT
        { : s fv ( nurl_lex_val lex )
            ( nurl_lex_advance lex )
            ( nurl_print `@` ) ( nurl_print cname )
            ( nurl_print ` = global double ` ) ( nurl_print fv ) ( nurl_print `\n\n` )
            ( nurl_sym_def syms cname `double` )
            ( nurl_sym_def syms ( nurl_str_cat cname `__global` ) `1` )
            ? is_mutable
            { ( nurl_sym_def syms ( nurl_str_cat cname `__mutable` ) `1` ) }
            {}
            // TEMPORARILY DISABLED: ( nurl_sym_def syms ( nurl_str_cat cname `__newsyntax` ) `1` )
        }
        ? == tt TT_BOOL
        { : s bv ( nurl_lex_val lex )
            ( nurl_lex_advance lex )
            ( nurl_print `@` ) ( nurl_print cname )
            ( nurl_print ` = global i1 ` )
            ( nurl_print ? ( seq bv `T` ) `1` `0` ) ( nurl_print `\n\n` )
            ( nurl_sym_def syms cname `i1` )
            ( nurl_sym_def syms ( nurl_str_cat cname `__global` ) `1` )
            ? is_mutable
            { ( nurl_sym_def syms ( nurl_str_cat cname `__mutable` ) `1` ) }
            {}
            // TEMPORARILY DISABLED: ( nurl_sym_def syms ( nurl_str_cat cname `__newsyntax` ) `1` )
        }
        ? == tt TT_STR
        { : s sv ( nurl_lex_val lex )
            ( nurl_lex_advance lex )
            : s enc ( encode_str sv 0 ( nurl_str_len sv ) )
            : i totlen + ( nurl_str_len sv ) 1
            : s slen_s ( nurl_str_int totlen )
            : s strname ( nurl_str_cat `@__const_` cname )
            ( nurl_print strname ) ( nurl_print ` = private unnamed_addr constant [` )
            ( nurl_print slen_s ) ( nurl_print ` x i8] c"` )
            ( nurl_print enc ) ( nurl_print `\00"\n` )
            ( nurl_print `@` ) ( nurl_print cname )
            ( nurl_print ` = global i8* getelementptr ([` )
            ( nurl_print slen_s ) ( nurl_print ` x i8], [` )
            ( nurl_print slen_s ) ( nurl_print ` x i8]* ` )
            ( nurl_print strname ) ( nurl_print `, i64 0, i64 0)\n\n` )
            ( nurl_sym_def syms cname `i8*` )
            ( nurl_sym_def syms ( nurl_str_cat cname `__global` ) `1` )
        }
        { ( nurl_lex_advance lex ) }  // unknown literal — skip
    }
    { ( nurl_lex_advance lex ) }
}

// ── FFI declaration: & `lib` @ name params... ('...')? → type ─────
// Emits a `declare` for an external C function.
//
// Variadic FFI (grammar v1.9): when the param list ends with the literal
// `...` token, the function is recorded as variadic. The fixed-param
// count is stashed in `<fname>__variadic_fixed`; gen_call consults this
// to apply C default argument promotions (float→double, narrow ints →
// i32) to every arg beyond the fixed count. Example:
//
//   & `libc` @ printf s fmt ... → i32
//
// The fname-keyed flag `<fname>__variadic` is the predicate; the count
// is needed because promotion applies ONLY to the variadic tail.

// __ffi_lib_check: enforce that every external `&`-FFI library has a
// corresponding build-time sentinel `stdlib/runtime.<name>` so a
// missing dev package surfaces as a clear compile-time error instead
// of a cryptic `undefined reference to PQconnectdb` from the linker.
//
// Normalisation: strip a leading `lib` prefix so `libcurl` matches
// the build.sh convention `stdlib/runtime.curl`. Whitelist: `c` /
// `libc` / `m` / `pthread` / `dl` are always linked (default link
// line in `build.sh` / `run_tests.sh`) and skip the check.
@ __ffi_lib_check i lex s lib → v {
    : i llen ( nurl_str_len lib )
    ? > llen 0 {
        // Strip a leading `lib` prefix if present (`libcurl` → `curl`).
        : ~ s norm lib
        ? & >= llen 3
          & == ( nurl_str_get lib 0 ) 108
          & == ( nurl_str_get lib 1 ) 105
            == ( nurl_str_get lib 2 ) 98
        { = norm ( nurl_str_slice lib 3 - llen 3 ) } {}
        // Whitelist: always-linked system libs (`c`/`m`/`pthread`/`dl`) plus
        // NURL-shipped FFI bridges (`canvas`, `audio`) whose backing C lives
        // in `stdlib/canvas*.c` / `stdlib/audio_wasm.c` and is linked by
        // `nurl.sh` / `wasmnurl.sh` — they have no `stdlib/runtime.*` sentinel.
        : b is_sys | ( seq norm `c` ) ( seq norm `m` )
        : b is_thr | ( seq norm `pthread` ) ( seq norm `dl` )
        : b is_brg | ( seq norm `canvas` ) ( seq norm `audio` )
        : b in_whitelist | | is_sys is_thr is_brg
        ? in_whitelist {} {
            : s sentinel ( nurl_str_cat `stdlib/runtime.` norm )
            ? == ( nurl_file_exists sentinel ) 1 {} {
                : s msg ( nurl_str_cat4
                    `FFI library '` lib `' is required but no build-time sentinel '`
                    ( nurl_str_cat sentinel `' found - install lib` ) )
                : s msg2 ( nurl_str_cat3 msg norm `-dev (or equivalent) and run build.sh again` )
                ( die lex msg2 )
            }
        }
    } {}
}

@ gen_ffi_decl i lex i syms → v {
    // Grammar v2.0+: `pub` on FFI decls is accepted at parse time
    // (forward-compat) but not enforced — FFI symbols are linker-
    // level ABI globals, the linker doesn't know about NURL files.
    ( vis_take_pending_pub )
    ( nurl_lex_advance lex )  // consume '&'
    // Library STR: skipped for IR emission (LLVM declare carries no
    // library name) but used for the build-time sentinel check so a
    // missing dev package fails fast at compile rather than at link.
    : s lib ( nurl_lex_val lex )
    ( __ffi_lib_check lex lib )
    ( nurl_lex_advance lex )  // skip library STR
    ( expect lex TT_AT )  // consume '@'
    : s fname ( nurl_lex_val lex )
    ( nurl_lex_advance lex )
    : s params_str ``
    : i pct 0
    ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF {
        ? == ( nurl_lex_type lex ) TT_ELLIPSIS
        { ( nurl_lex_advance lex )  // consume '...'
            // Register variadic side-channel: the predicate flag and the
            // fixed-param count (decimal-stringified) drive the call-site
            // promotion path in gen_call.
            ( nurl_sym_def syms ( nurl_str_cat fname `__variadic` ) `1` )
            ( nurl_sym_def syms ( nurl_str_cat fname `__variadic_fixed` ) ( nurl_str_int pct ) )
            = params_str ? == pct 0 `...` ( nurl_str_cat params_str `, ...` )
        }
        { : s lt ( parse_type lex )
            ? ( is_ident_tok ( nurl_lex_type lex ) ) { ( nurl_lex_advance lex ) } {}
            ? == pct 0
            { = params_str lt }
            { = params_str ( nurl_str_cat params_str ( nurl_str_cat `, ` lt ) ) }
            = pct + pct 1
        }
    }
    ( expect lex TT_ARROW )
    : s ret_ty ( parse_type lex )
    ( nurl_sym_def syms fname ret_ty )
    // emit_header already emits `declare` lines for a small set of libc
    // symbols (malloc, free, puts, printf). If the user FFI-declares any of
    // those, re-emitting the same `declare` would trigger LLVM's "invalid
    // redefinition of function" error, so skip the emit — the symbol is
    // still registered above so callers resolve correctly.
    : b is_prelude_cfn | | | ( seq fname `malloc` ) ( seq fname `free` ) ( seq fname `puts` ) ( seq fname `printf` )
    ? is_prelude_cfn
    {}
    { ( nurl_print `declare ` ) ( nurl_print ret_ty )
        ( nurl_print ` @` ) ( nurl_print fname )
        ( nurl_print `(` ) ( nurl_print params_str ) ( nurl_print `)\n\n` )
    }
}

// Check if current token could be a payload type (without consuming it)
@ could_be_payload_type i lex i syms → b {
    : i tt ( nurl_lex_type lex )
    ? | == tt TT_TYPE_KW | == tt TT_STAR | == tt TT_QUEST | == tt TT_LBRACK | == tt TT_BANG == tt TT_LPAREN
    ^ T
    ? == tt TT_IDENT
    { : s maybe ( nurl_lex_val lex )
        : s entry ( nurl_sym_get syms maybe )
        ^ & != 0 ( nurl_str_len entry ) == ( nurl_str_get entry 0 ) 37
    }
    ^ F
}

// ── Enum declaration: : | Name { Variant (type?)* } ───────────────
// Each variant becomes a global i64 constant (tag value 0, 1, …).

@ gen_enum_decl i lex i syms → v {
    ( nurl_lex_advance lex )  // consume '|'
    : s ename ( nurl_lex_val lex )
    ( nurl_lex_advance lex )  // consume enum name
    // Grammar v2.0+: consume the staged `pub` flag for the whole
    // enum. Variants inherit the parent enum's visibility — there is
    // no per-variant `pub` syntax.
    : b enum_pub ( vis_take_pending_pub )
    ( vis_record_type ename enum_pub )
    ( nurl_print `; enum ` ) ( nurl_print ename ) ( nurl_print `\n` )
    ( expect lex TT_LBRACE )
    : i tag 0
    : i max_payloads 0
    : s variants_str ``
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        : s vname ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        = variants_str ? == 0 ( nurl_str_len variants_str )
        vname
        ( nurl_str_cat variants_str ( nurl_str_cat ` ` vname ) )
        ( nurl_print `@` ) ( nurl_print vname )
        ( nurl_print ` = global i64 ` )
        ( nurl_print ( nurl_str_int tag ) ) ( nurl_print `\n` )
        ( nurl_sym_def syms vname `i64` )
        ( nurl_sym_def syms ( nurl_str_cat vname `__global` ) `1` )
        // Per-variant visibility = enum's visibility. Records origin so
        // a bare-variant use site (`# NetErr NetBind`) can be cross-
        // file-checked the same way @-fn calls are.
        ( vis_record_const vname enum_pub )
        = tag + tag 1
        // Collect payload types indexed: vname__payload__0, vname__payload__1, ...
        // TYPE_KW / sigils → always a type, never a variant name.
        // IDENT → payload only if it is a known struct type (starts with '%' in syms).
        : i pcount 0
        ~ & != ( nurl_lex_type lex ) TT_RBRACE ( could_be_payload_type lex syms ) {
            : s pt ( parse_type lex )
            ( nurl_sym_def syms ( nurl_str_cat vname ( nurl_str_cat `__payload__` ( nurl_str_int pcount ) ) ) pt )
            = pcount + pcount 1
        }
        ( nurl_sym_def syms ( nurl_str_cat vname `__paycount` ) ( nurl_str_int pcount ) )
        ? > pcount max_payloads { = max_payloads pcount } {}
    }
    ( expect lex TT_RBRACE )
    ( nurl_sym_def syms ( nurl_str_cat ename `__variants` ) variants_str )
    // Side-band: enums whose largest variant has at least one payload slot
    // are too wide to fit in the 8-byte payload of `! T E`. gen_agg_lit
    // and gen_match consult this to decide between i64-tag-fold (no payloads)
    // and heap-box (has payloads). See "wide enum" comments at those sites.
    ( nurl_sym_def syms ( nurl_str_cat ename `__max_payloads` ) ( nurl_str_int max_payloads ) )

    // Generate LLVM type declaration: { i64, ptr, ptr, ... } with max_payloads ptr slots
    ( nurl_print `%` ) ( nurl_print ename )
    ( nurl_print ` = type { i64` )
    : i pi 0
    ~ < pi max_payloads {
        ( nurl_print `, ptr` )
        = pi + pi 1
    }
    ( nurl_print ` }\n` )

    // Register the enum type in symbol table
    ( nurl_sym_def syms ename ( nurl_str_cat `%` ename ) )
    ( nurl_sym_def syms ( nurl_str_cat ename `__is_type` ) `1` )

    ( nurl_print `\n` )
}

// ── Import declaration: $ `path` alias? ───────────────────────────
// Reads and compiles the referenced .nu file inline (static include).
// When an alias is present, every top-level decl name defined in the
// imported file is renamed in the file's source to `alias__name`
// before compilation. Callers can then reach those decls via the
// namespace syntax `alias::name`, which the lexer merges into a single
// IDENT `alias__name`.
//
// Names that ARE rewritten by `collect_alias_targets`:
//   * top-level `@ name`           — function definitions
//   * top-level `: Name { ... }`   — struct types
//   * top-level `: | Name { ... }` — enum types + every variant inside
//   * top-level `: TYPE_KW NAME …` — global constants
//
// Names that are NOT rewritten (intentional):
//   * `& "lib" @ name`             — FFI declarations. The linker resolves
//                                    the C-side ABI symbol by literal name;
//                                    renaming would either break the link
//                                    (if applied to the FFI side too) or
//                                    leave use sites referencing an undefined
//                                    symbol (if applied only at the call site).
//                                    Use `pub` instead if you want to keep
//                                    FFI scoped to the importing file.
//   * `% Trait [T] { ... }`        — trait methods are mangled by the
//                                    impl-target type at emission time;
//                                    they aren't looked up by name across
//                                    files in the first place.
//   * struct-field names, closure params, locals — never top-level decls.
@ collect_alias_targets s src s path → s {
    : i lx ( nurl_lex_new src path )
    : ~ s names ``
    : ~ i depth 0
    ~ != ( nurl_lex_type lx ) TT_EOF {
        : i tt ( nurl_lex_type lx )
        ? == tt TT_LBRACE
        { = depth + depth 1 ( nurl_lex_advance lx ) }
        { ? == tt TT_RBRACE
            { = depth - depth 1 ( nurl_lex_advance lx ) }
            { ? & == depth 0 == tt TT_AMP
                {  // FFI: skip '& STR @ IDENT' so the FFI target name is not collected
                    ( nurl_lex_advance lx )
                    ? == ( nurl_lex_type lx ) TT_STR { ( nurl_lex_advance lx ) } {}
                    ? == ( nurl_lex_type lx ) TT_AT { ( nurl_lex_advance lx ) } {}
                    ? ( is_ident_tok ( nurl_lex_type lx ) ) { ( nurl_lex_advance lx ) } {}
                }
                { ? & == depth 0 == tt TT_DOLLAR
                    {  // Nested import: skip path STR + optional alias IDENT
                        ( nurl_lex_advance lx )
                        ? == ( nurl_lex_type lx ) TT_STR { ( nurl_lex_advance lx ) } {}
                        ? ( is_ident_tok ( nurl_lex_type lx ) ) { ( nurl_lex_advance lx ) } {}
                    }
                    { ? & == depth 0 == tt TT_AT
                        { ( nurl_lex_advance lx )
                            ? ( is_ident_tok ( nurl_lex_type lx ) )
                            { : s n ( nurl_lex_val lx )
                                = names ? == 0 ( nurl_str_len names )
                                n
                                ( nurl_str_cat3 names ` ` n )
                                ( nurl_lex_advance lx )
                            }
                            {}
                        }
                        { ? & == depth 0 == tt TT_PUB
                            {  // `pub` prefix on any decl — skip the keyword,
                               // the following decl will be picked up by its
                               // own branch on the next iteration.
                                ( nurl_lex_advance lx )
                            }
                            { ? & == depth 0 == tt TT_COLON
                                { ( nurl_lex_advance lx )  // consume ':'
                                    // Optional mutable marker on a const.
                                    ? == ( nurl_lex_type lx ) TT_TILDE { ( nurl_lex_advance lx ) } {}
                                    : i tt2 ( nurl_lex_type lx )
                                    ? == tt2 TT_PIPE
                                    {  // `: | Name { Variant1 Variant2(payload?) ... }`
                                        ( nurl_lex_advance lx )  // consume '|'
                                        ? ( is_ident_tok ( nurl_lex_type lx ) )
                                        { : s en ( nurl_lex_val lx )
                                            = names ? == 0 ( nurl_str_len names ) en ( nurl_str_cat3 names ` ` en )
                                            ( nurl_lex_advance lx )
                                        } {}
                                        // Walk into the body and collect variant
                                        // names. Each variant is `Name optional-payload-tys`;
                                        // a TYPE_KW or sigil token (`*`, `?`, `[`,
                                        // `!`, `(`) introduces a payload type, not
                                        // a variant — skip those. IDENTs that are
                                        // already on `names` (e.g. nested struct
                                        // type appearing as a payload) are noticed
                                        // by alias_rewrite_source's whole-identifier
                                        // dedup.
                                        ? == ( nurl_lex_type lx ) TT_LBRACE
                                        { ( nurl_lex_advance lx )
                                            ~ & != ( nurl_lex_type lx ) TT_RBRACE != ( nurl_lex_type lx ) TT_EOF {
                                                ? ( is_ident_tok ( nurl_lex_type lx ) )
                                                { : s vn ( nurl_lex_val lx )
                                                    = names ? == 0 ( nurl_str_len names ) vn ( nurl_str_cat3 names ` ` vn )
                                                    ( nurl_lex_advance lx )
                                                } { ( nurl_lex_advance lx ) }
                                            }
                                            ? == ( nurl_lex_type lx ) TT_RBRACE { ( nurl_lex_advance lx ) } {}
                                        } {}
                                    }
                                    { ? == tt2 TT_TYPE_KW
                                        {  // `: TYPE_KW NAME value` (global const).
                                            // Checked BEFORE the IDENT branch because
                                            // is_ident_tok matches TYPE_KW too — a
                                            // bare `i` / `s` / `f` etc. would otherwise
                                            // be mistaken for a struct name.
                                            ( nurl_lex_advance lx )  // consume type kw
                                            ? ( is_ident_tok ( nurl_lex_type lx ) )
                                            { : s cn ( nurl_lex_val lx )
                                                = names ? == 0 ( nurl_str_len names ) cn ( nurl_str_cat3 names ` ` cn )
                                                ( nurl_lex_advance lx )
                                            } {}
                                        }
                                        { ? == tt2 TT_IDENT
                                            {  // `: Name { ... }` (struct) OR
                                               // `: Name [tparams] { ... }` (generic struct).
                                                : s sn ( nurl_lex_val lx )
                                                = names ? == 0 ( nurl_str_len names ) sn ( nurl_str_cat3 names ` ` sn )
                                                ( nurl_lex_advance lx )
                                            }
                                            {}
                                        }
                                    }
                                }
                                { ( nurl_lex_advance lx ) }
                            }
                        }
                    }
                }
            }
        }
    }
    names
}

// alias_rewrite_source: return a copy of `src` where every whole-identifier
// occurrence that appears in the space-separated `names` list is prefixed
// with `prefix`. Identifiers inside backtick string literals and `//` line
// comments are preserved verbatim so that name mangling does not touch
// strings or documentation.
@ alias_rewrite_source s src s names s prefix → s {
    : s result ``
    : i slen ( nurl_str_len src )
    : i pos 0
    : i word_start 0
    : i in_string 0  // 1 while scanning inside a backtick-delimited string
    : i in_comment 0  // 1 while scanning inside a // line comment
    ~ < pos slen {
        : i ch ( nurl_str_get src pos )
        ? != in_string 0
        { = result ( nurl_str_cat result ( nurl_str_slice src pos 1 ) )
            ? == ch 96 { = in_string 0 } {}
            = pos + pos 1
            = word_start pos
        }
        { ? != in_comment 0
            { = result ( nurl_str_cat result ( nurl_str_slice src pos 1 ) )
                ? == ch 10 { = in_comment 0 } {}
                = pos + pos 1
                = word_start pos
            }
            { : b is_id ( __is_ident_char ch )
                ? is_id
                { = pos + pos 1 }
                { ? > pos word_start
                    { : s word ( nurl_str_slice src word_start - pos word_start )
                        = result ( nurl_str_cat result
                        ? ( str_contains_word names word )
                        ( nurl_str_cat prefix word )
                        word )
                    }
                    {}
                    : i nxt ? < + pos 1 slen ( nurl_str_get src + pos 1 ) 0
                    ? & == ch 47 == nxt 47
                    { = result ( nurl_str_cat result ( nurl_str_slice src pos 2 ) )
                        = in_comment 1
                        = pos + pos 2
                    }
                    { ? == ch 96
                        { = result ( nurl_str_cat result ( nurl_str_slice src pos 1 ) )
                            = in_string 1
                            = pos + pos 1
                        }
                        { = result ( nurl_str_cat result ( nurl_str_slice src pos 1 ) )
                            = pos + pos 1
                        }
                    }
                    = word_start pos
                }
            }
        }
    }
    ? > pos word_start
    { : s word ( nurl_str_slice src word_start - pos word_start )
        = result ( nurl_str_cat result
        ? ( str_contains_word names word )
        ( nurl_str_cat prefix word )
        word )
    }
    {}
    result
}

@ gen_import_decl i lex i syms i cg → v {
    ( nurl_lex_advance lex )  // consume '$'
    : s path ( __norm_import_path ( nurl_lex_val lex ) )
    ( nurl_lex_advance lex )  // consume path STR
    : s alias ``
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { = alias ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
    }
    {}

    ? ( mem_is_imported syms path )
    {}
    { ( mem_mark_imported syms path )
        : s src ( nurl_read_file path )
        : s eff_src ? != 0 ( nurl_str_len alias )
        { : s names ( collect_alias_targets src path )
            ( alias_rewrite_source src names ( nurl_str_cat alias `__` ) )
        }
        src
        // Save / restore the current source-file across the nested scan
        // + parse passes so vis_record_fn and gen_call attribute decls
        // (and visibility checks) to the imported file's path, not the
        // importer's.
        : s saved_sf ( vis_current_src_file )
        ( vis_set_current_src_file path )
        : i lex2 ( nurl_lex_new eff_src path )
        ( scan_fn_sigs lex2 syms )
        : i lex3 ( nurl_lex_new eff_src path )
        ( parse_program lex3 syms cg )
        ( vis_set_current_src_file saved_sf )
    }
}

// ── Generic instantiation flush (Group E) ────────────────────────────
// emit_one_instantiation: build and emit one monomorphised function.
//
// Substitutes T → ConcreteTy in the stored template source, then re-lexes
// twice: once to scan for nested generic-struct instantiations whose type
// args are now concrete (so the corresponding `%Name__Tconcrete` named
// types + field metadata exist before the body references them — fixes
// the "two generic structs side-by-side" case where a generic function
// returns `( B T )` but internally allocates `*( A T )` and writes its
// fields), then again to actually emit the function. The two passes
// share `syms` so the rescan's emitted instantiations are visible to
// the body-parsing pass.
@ emit_one_instantiation s fname s mangled s type_args i syms i cg → v {
    : s tparams ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
    : s gsrc ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__gsrc` ) )
    : s subst_src gsrc
    : s tp_rest tparams
    : s ta_rest type_args
    ~ != 0 ( nurl_str_len tp_rest ) {
        : s tp ( str_first_word tp_rest )
        = tp_rest ( str_skip_word tp_rest )
        : s ta ( str_first_word ta_rest )
        = ta_rest ( str_skip_word ta_rest )
        = subst_src ( subst_source subst_src tp ta )
    }
    : s full_src ( nurl_str_cat `@ ` ( nurl_str_cat mangled ( nurl_str_cat ` ` subst_src ) ) )
    : i lex_scan ( nurl_lex_new full_src `<generic-scan>` )
    ( scan_generic_structs lex_scan syms )
    : i lex2 ( nurl_lex_new full_src `<generic>` )
    // DWARF Phase 7: stash the original generic-decl line so
    // gen_fn_decl_concrete points this mono's !DISubprogram at the
    // real source, not the synthetic `<generic>:1`. Cleared in a
    // `defer`-ish trailing assignment after the recursive call.
    : i saved_override g_dbg_override_line
    : s sl_s ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__src_line` ) )
    ? != 0 ( nurl_str_len sl_s )
    { = g_dbg_override_line ( nurl_str_to_int sl_s ) }
    {}
    ( gen_fn_decl lex2 syms cg )
    = g_dbg_override_line saved_override
}

// flush_deferred_instantiations: emit all queued generic instantiations.
// Re-reads count each iteration so transitive generics are also emitted.
@ flush_deferred_instantiations i syms i cg → v {
    : i k 0
    ~ < k ( nurl_str_to_int ( nurl_sym_get g_generic_syms `__deferred_count__` ) ) {
        : s base ( nurl_str_cat `__def` ( nurl_str_int k ) )
        : s fname ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_fn` ) )
        : s mangled ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_mn` ) )
        : s type_args ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_ta` ) )
        ( emit_one_instantiation fname mangled type_args syms cg )
        = k + k 1
    }
}

// ── Module header ──────────────────────────────────────────────────

@ emit_header → v {
    ( emit `; NURL compiler output (nurlc.nu)` )
    ( emit `; link: clang <this.ll> stdlib/runtime.o -o out` )
    ( emit `` )
    // DWARF Phase 5: the dbg.declare intrinsic that pins a local
    // variable's storage to its !DILocalVariable metadata. Emitted
    // unconditionally; with --g off the compiler never calls it, so
    // the unused declaration is dead and the optimizer drops it.
    ( emit `declare void @llvm.dbg.declare(metadata, metadata, metadata)` )
    ( emit `declare i32  @puts(i8*)` )
    ( emit `declare i32  @printf(i8*, ...)` )
    ( emit `declare i8*  @malloc(i64)` )
    ( emit `declare void @free(i8*)` )
    // libc string / parse primitives — used by pure-NURL replacements
    // for the historic `nurl_str_*` C wrappers (PURIFY.md Phase 5,
    // 2026-05-23). These are globally-callable from NURL programs
    // and from `nurlc.nu` itself. Returns mapped at their native C
    // widths (i32 for int-returners, i8* for ptr-returners); NURL
    // callers do their own widening via `# i` if they need i64.
    ( emit `declare i64  @strlen(i8*)` )
    ( emit `declare i32  @strcmp(i8*, i8*)` )
    ( emit `declare i32  @strncmp(i8*, i8*, i64)` )
    ( emit `declare i32  @memcmp(i8*, i8*, i64)` )
    ( emit `declare i8*  @strstr(i8*, i8*)` )
    ( emit `declare i8*  @memmem(i8*, i64, i8*, i64)` )
    ( emit `declare i64  @atoll(i8*)` )
    ( emit `declare double @atof(i8*)` )
    ( emit `declare double @strtod(i8*, i8**)` )
    ( emit `declare i8*  @memcpy(i8*, i8*, i64)` )
    ( emit `declare i8*  @strdup(i8*)` )
    // libc stdio primitives — used by pure-NURL replacements for the
    // historic `nurl_file_*` C wrappers (PURIFY.md Phase 7, 2026-05-23).
    ( emit `declare i8*  @fopen(i8*, i8*)` )
    ( emit `declare i32  @fclose(i8*)` )
    ( emit `declare i32  @fputs(i8*, i8*)` )
    ( emit `declare i64  @fwrite(i8*, i64, i64, i8*)` )
    ( emit `declare i32  @fputc(i32, i8*)` )
    ( emit `declare i64  @fread(i8*, i64, i64, i8*)` )
    ( emit `declare i32  @feof(i8*)` )
    // POSIX access(2) for nurl_file_exists pure-NURL @-fn (Phase 7).
    ( emit `declare i32  @access(i8*, i32)` )
    ( emit `declare void @nurl_init(i32, i8**)` )
    ( emit `declare void @nurl_print(i8*)` )
    ( emit `declare void @nurl_eprint(i8*)` )
    ( emit `declare void @nurl_eprintln(i8*)` )
    ( emit `declare void @nurl_print_int(i64)` )
    ( emit `declare void @nurl_print_str(i8*)` )
    ( emit `declare void @nurl_print_bool(i1)` )
    ( emit `declare i64  @nurl_read_int()` )
    ( emit `declare i8*  @nurl_read_line()` )
    ( emit `declare i8*  @nurl_read_n_bytes(i64)` )
    ( emit `declare i64  @nurl_stdin_eof()` )
    ( emit `declare void @nurl_flush_stdout()` )
    ( emit `declare void @nurl_flush_stderr()` )
    // PURIFY.md Phase 5 Batch C (2026-05-23): nurl_str_get / _cat /
    // _cat3 / _cat4 / _slice / _parse_int_range are pure-NURL @-fns
    // now — declares dropped to avoid clashing with their `define`s
    // in user code (and the local copies inside nurlc.nu itself).
    // Batch D' (2026-05-23): _parse_float_range joined them via
    // strtod. _str_int stays in C — 72 corpus tests use it without
    // importing stdlib/core/string.nu, and the cost-vs-savings
    // doesn't justify churning them until a prelude lands. Only
    // _str_float (printf-family %g, Grisu/Ryu TODO) stays beside it.
    ( emit `declare i8*  @nurl_str_int(i64)` )
    ( emit `declare i8*  @nurl_str_float(double)` )
    // PURIFY.md Phase 5 (2026-05-23): nurl_str_len / _eq / _cmp /
    // _to_int / _to_float / _starts / _find / _ends / _memmem_range /
    // _memcmp_lex are pure-NURL @-fns now (libc-thin wrappers
    // calling strlen / strcmp / strncmp / strstr / memcmp / memmem /
    // atoll / atof directly via the global preamble declarations
    // emitted above).
    ( emit `declare i64    @nurl_csv_scan_cell(i8*, i64, i64)` )
    ( emit `declare i64    @nurl_csv_filter_float_gt(i8*, i8*, i64*, i64*, i64*, i64, i64, double)` )
    ( emit `declare i64    @nurl_csv_filter_str_contains(i8*, i8*, i64*, i64*, i64*, i64, i64, i8*, i64)` )
    ( emit `declare i64    @nurl_csv_filter_float_gt_and_str_contains(i8*, i8*, i64*, i64*, i64*, i64, i64, double, i64, i8*, i64)` )
    ( emit `declare i64    @nurl_csv_filter_typed_float_gt(double*, i64*, i64*, i64, double)` )
    ( emit `declare i64    @nurl_has_byte(i8*, i64, i64)` )
    ( emit `declare i64    @nurl_count_byte(i8*, i64, i64)` )
    ( emit `declare double @nurl_csv_fast_float_range(i8*, i64)` )
    ( emit `declare i64    @nurl_csv_parse_arena(i8*, i64, i64, i64*, i64, i64*, i64*, i64, i64*, i64)` )
    ( emit `declare i64    @nurl_csv_n_rows_out()` )
    ( emit `declare i64    @nurl_csv_n_header_out()` )
    ( emit `declare i64    @nurl_csv_n_cells_out()` )
    ( emit `declare i64    @nurl_csv_scan_row_pairs(i8*, i64, i64, i64, i64*, i64)` )
    ( emit `declare i64    @nurl_csv_row_n_cells_out()` )
    ( emit `declare i64    @nurl_csv_row_next_pos_out()` )
    // nurl_str_slice — pure-NURL @-fn (PURIFY.md Phase 5 Batch C).
    ( emit `declare i64  @nurl_map_new()` )
    ( emit `declare void @nurl_map_put(i64, i8*, i64)` )
    ( emit `declare i64  @nurl_map_get(i64, i8*)` )
    ( emit `declare i64  @nurl_map_has(i64, i8*)` )
    ( emit `declare void @nurl_map_del(i64, i8*)` )
    ( emit `declare i64  @nurl_map_size(i64)` )
    ( emit `declare void @nurl_map_free(i64)` )
    ( emit `declare i8*  @nurl_read_file(i8*)` )
    ( emit `declare void @nurl_exit(i64)` )
    ( emit `declare i64  @nurl_argc()` )
    ( emit `declare i8*  @nurl_argv(i64)` )
    ( emit `declare i64  @nurl_argv_count()` )
    ( emit `declare i8*  @nurl_argv_get(i64)` )
    ( emit `declare i64  @nurl_lex_new(i8*, i8*)` )
    ( emit `declare i64  @nurl_lex_type(i64)` )
    ( emit `declare i8*  @nurl_lex_val(i64)` )
    ( emit `declare i64    @nurl_lex_inum(i64)` )
    ( emit `declare double @nurl_lex_fnum(i64)` )
    ( emit `declare void   @nurl_lex_advance(i64)` )
    ( emit `declare i64  @nurl_lex_peek_type(i64)` )
    ( emit `declare i64  @nurl_lex_peek2_type(i64)` )
    ( emit `declare i64  @nurl_lex_peek3_type(i64)` )
    ( emit `declare i64  @nurl_lex_peek4_type(i64)` )
    ( emit `declare i64  @nurl_lex_line(i64)` )
    ( emit `declare i64  @nurl_lex_col(i64)` )
    ( emit `declare i8*  @nurl_lex_line_text(i64)` )
    ( emit `declare i8*  @nurl_diag_caret(i64)` )
    ( emit `declare i64  @nurl_lex_cur_start(i64)` )
    ( emit `declare i8*  @nurl_lex_src_slice(i64, i64, i64)` )
    ( emit `declare void @nurl_lex_set_pos(i64, i64)` )
    ( emit `declare void @nurl_print_buf_start()` )
    ( emit `declare i8*  @nurl_print_buf_stop()` )
    ( emit `declare void @nurl_print_buf_reset()` )
    ( emit `declare i8*  @nurl_lex_filename(i64)` )
    ( emit `declare i64  @nurl_sym_new()` )
    ( emit `declare void @nurl_sym_def(i64, i8*, i8*)` )
    ( emit `declare i8*  @nurl_sym_get(i64, i8*)` )
    ( emit `declare void @nurl_sym_push(i64)` )
    ( emit `declare void @nurl_sym_pop(i64)` )
    ( emit `declare i64  @nurl_cg_new()` )
    ( emit `declare i8*  @nurl_cg_reg(i64)` )
    ( emit `declare i8*  @nurl_cg_lbl(i64, i8*)` )
    ( emit `declare void @nurl_cg_reset(i64)` )
    ( emit `declare i8*  @nurl_get_last_type()` )
    ( emit `declare void @nurl_set_last_type(i8*)` )
    ( emit `declare i8*  @nurl_malloc(i64)` )
    ( emit `declare i8*  @nurl_alloc(i64)` )
    ( emit `declare i8*  @nurl_zalloc(i64)` )
    ( emit `declare i8*  @nurl_realloc(i8*, i64)` )
    ( emit `declare void @nurl_free(i8*)` )
    ( emit `declare void @nurl_memcpy(i8*, i8*, i64)` )
    ( emit `declare void @nurl_memset(i8*, i64, i64)` )
    ( emit `declare i64  @nurl_peek(i8*, i64)` )
    ( emit `declare void @nurl_poke(i8*, i64, i64)` )
    // PURIFY.md Phase 7 (2026-05-23): nurl_file_open / _write /
    // _write_range / _write_byte / _close / _read_chunk / _eof are
    // pure-NURL @-fns now in stdlib/std/fs.nu, calling libc fopen /
    // fputs / fwrite / fputc / fclose / fread / feof directly.
    ( emit `declare i8*  @nurl_file_read(i8*)` )
    // PURIFY.md Phase 7 (2026-05-23): nurl_file_exists / _del /
    // _dir_create / _dir_remove are pure-NURL @-fns in
    // stdlib/std/fs.nu, calling libc access / remove / mkdir / rmdir.
    // _file_size needs `struct stat` and stays in C.
    ( emit `declare i64  @nurl_file_size(i8*)` )
    ( emit `declare i8*  @nurl_read_file_safe(i8*)` )
    ( emit `declare i8*  @nurl_read_file_mmap(i8*)` )
    ( emit `declare i64  @nurl_write_file_safe(i8*, i8*, i8*)` )
    ( emit `declare i64  @nurl_errno_kind()` )
    // libm wrappers (nurl_sqrt / _fabs / _floor / _ceil / _round /
    // _pow / _log / _exp / _sin / _cos / _tan / _atan2) and
    // nurl_iabs / _ipow — moved to pure-NURL (libm direct FFI in
    // stdlib/std/float.nu; iabs/ipow as plain @-fns in
    // stdlib/std/int.nu) as PURIFY.md Phase 3 (2026-05-23).
    ( emit `declare i64    @nurl_is_nan(double)` )
    ( emit `declare i64    @nurl_is_inf(double)` )
    ( emit `declare i64    @nurl_str_to_float_safe(i8*)` )
    ( emit `declare double @nurl_str_float_value()` )
    ( emit `declare i64  @nurl_now_ms()` )
    ( emit `declare i64  @nurl_now_seconds()` )
    ( emit `declare i64  @nurl_monotonic_ns()` )
    ( emit `declare void @nurl_sleep_ms(i64)` )
    ( emit `declare i8*  @nurl_env_get(i8*)` )
    ( emit `declare i64  @nurl_env_set(i8*, i8*)` )
    ( emit `declare i64  @nurl_env_unset(i8*)` )
    ( emit `declare i8*  @nurl_cwd()` )
    ( emit `declare i64  @nurl_chdir(i8*)` )
    ( emit `declare i8*  @nurl_read_all_stdin()` )
    ( emit `declare i64  @nurl_dir_list_open(i8*)` )
    ( emit `declare i8*  @nurl_dir_list_next(i64)` )
    ( emit `declare void @nurl_dir_list_close(i64)` )
    ( emit `declare i64  @nurl_http_perform_full(i8*, i8*, i8*, i8*)` )
    ( emit `declare i64  @nurl_http_perform_full_to(i8*, i8*, i8*, i8*, i64, i64)` )
    ( emit `declare i64  @nurl_http_response_status(i64)` )
    ( emit `declare i64  @nurl_http_response_err_kind(i64)` )
    ( emit `declare i8*  @nurl_http_response_body(i64)` )
    ( emit `declare i64  @nurl_http_response_body_len(i64)` )
    ( emit `declare i64  @nurl_http_response_header_count(i64)` )
    ( emit `declare i8*  @nurl_http_response_header_name(i64, i64)` )
    ( emit `declare i8*  @nurl_http_response_header_value(i64, i64)` )
    ( emit `declare void @nurl_http_response_free(i64)` )
    ( emit `declare i64  @nurl_http_stream_open_to(i8*, i8*, i8*, i8*, i64, i64)` )
    ( emit `declare i8*  @nurl_http_stream_next(i64)` )
    ( emit `declare i64  @nurl_http_stream_status(i64)` )
    ( emit `declare i64  @nurl_http_stream_err_kind(i64)` )
    ( emit `declare void @nurl_http_stream_close(i64)` )
    ( emit `declare i64  @nurl_http_stream_pump_headers(i64)` )
    ( emit `declare i64  @nurl_http_stream_header_count(i64)` )
    ( emit `declare i8*  @nurl_http_stream_header_name(i64, i64)` )
    ( emit `declare i8*  @nurl_http_stream_header_value(i64, i64)` )
    ( emit `declare i64  @nurl_proc_run(i8*, i8*, i64, i8*)` )
    ( emit `declare i64  @nurl_proc_exit_code(i64)` )
    ( emit `declare i64  @nurl_proc_err_kind(i64)` )
    ( emit `declare i8*  @nurl_proc_stdout(i64)` )
    ( emit `declare i8*  @nurl_proc_stderr(i64)` )
    ( emit `declare i64  @nurl_proc_stdout_len(i64)` )
    ( emit `declare i64  @nurl_proc_stderr_len(i64)` )
    ( emit `declare void @nurl_proc_free(i64)` )
    ( emit `declare i64  @nurl_proc_spawn(i8*, i8*, i64)` )
    ( emit `declare i64  @nurl_proc_spawn_err_kind(i64)` )
    ( emit `declare i64  @nurl_proc_spawn_pid(i64)` )
    ( emit `declare i64  @nurl_proc_spawn_write(i64, i8*, i64)` )
    ( emit `declare void @nurl_proc_spawn_close_stdin(i64)` )
    ( emit `declare i8*  @nurl_proc_spawn_read_line(i64, i64)` )
    ( emit `declare i64  @nurl_proc_spawn_read_line_len(i64)` )
    ( emit `declare i64  @nurl_proc_spawn_eof(i64)` )
    ( emit `declare i64  @nurl_proc_spawn_last_io_err(i64)` )
    ( emit `declare i64  @nurl_proc_spawn_wait(i64)` )
    ( emit `declare i64  @nurl_proc_spawn_kill(i64, i64)` )
    ( emit `declare void @nurl_proc_spawn_free(i64)` )
    // Crypto hash transforms (SHA-1/256/512, MD5, HMAC-SHA-256/512)
    // moved to pure NURL — `stdlib/std/hash_*.nu` — as PURIFY.md
    // Phase 4 (2026-05-23). Only `nurl_rand_*` stays C-side
    // (irreducible getrandom/RtlGenRandom syscall bridge).
    ( emit `declare i64  @nurl_rand_u64()` )
    ( emit `declare i8*  @nurl_rand_bytes_hex(i64)` )
    ( emit `declare i8*  @nurl_read_file_bytes(i8*)` )
    ( emit `declare i64  @nurl_write_file_bytes(i8*, i8*, i64, i8*)` )
    ( emit `declare i64  @nurl_last_bytes_len()` )
    ( emit `declare i64  @nurl_tcp_listen(i8*, i64, i64)` )
    ( emit `declare i64  @nurl_tcp_listen_tls(i8*, i64, i64, i8*, i8*)` )
    ( emit `declare i64  @nurl_tcp_listen_tls_alpn(i8*, i64, i64, i8*, i8*, i8*)` )
    ( emit `declare i8*  @nurl_tcp_alpn_selected(i64)` )
    ( emit `declare i64  @nurl_tcp_tls_add_sni(i64, i8*, i8*, i8*)` )
    ( emit `declare i64  @nurl_tcp_tls_reload(i64, i8*, i8*, i8*)` )
    ( emit `declare i64  @nurl_tcp_tls_require_client_cert(i64, i8*, i64)` )
    ( emit `declare i8*  @nurl_tcp_peer_cert_subject(i64)` )
    ( emit `declare i64  @nurl_dos_state_new(i64, i64)` )
    ( emit `declare i64  @nurl_dos_state_try_acquire(i64, i8*)` )
    ( emit `declare void @nurl_dos_state_release(i64, i8*)` )
    ( emit `declare void @nurl_dos_state_free(i64)` )
    ( emit `declare i64  @nurl_dos_state_active(i64)` )
    ( emit `declare i64  @nurl_tcp_accept(i64)` )
    ( emit `declare i64  @nurl_tcp_read(i64, i8*, i64)` )
    ( emit `declare i64  @nurl_tcp_write(i64, i8*, i64)` )
    ( emit `declare void @nurl_tcp_close(i64)` )
    ( emit `declare void @nurl_tcp_shutdown(i64)` )
    ( emit `declare i64  @nurl_tcp_err_kind(i64)` )
    ( emit `declare i8*  @nurl_tcp_peer_addr(i64)` )
    ( emit `declare void @nurl_tcp_set_timeout(i64, i64)` )
    // Thread / mutex / cond moved to pure-NURL FFI in stdlib/std/thread.nu
    // (PURIFY.md Phase 6) — libpthread symbols (pthread_create / mutex_*
    // / cond_*) plus the tiny nurl_pthread_join_ptr / _detach_ptr
    // trampolines are declared on-demand in that module via `& `c` @ ...`.
    ( emit `declare void @nurl_signal_install_shutdown(i64)` )
    ( emit `declare void @nurl_signal_trigger_shutdown()` )
    ( emit `declare void @nurl_panic(i8*)` )
    ( emit `declare i64  @nurl_recover(i8*, i8*)` )
    ( emit `declare i8*  @nurl_panic_last_msg()` )
    ( emit `declare i64  @nurl_sqlite_open(i8*)` )
    ( emit `declare void @nurl_sqlite_close(i64)` )
    ( emit `declare i64  @nurl_sqlite_err_kind(i64)` )
    ( emit `declare i8*  @nurl_sqlite_errmsg(i64)` )
    ( emit `declare i64  @nurl_sqlite_exec(i64, i8*)` )
    ( emit `declare i64  @nurl_sqlite_prepare(i64, i8*)` )
    ( emit `declare i64  @nurl_sqlite_stmt_err_kind(i64)` )
    ( emit `declare i64  @nurl_sqlite_bind_int(i64, i64, i64)` )
    ( emit `declare i64  @nurl_sqlite_bind_text(i64, i64, i8*)` )
    ( emit `declare i64  @nurl_sqlite_bind_null(i64, i64)` )
    ( emit `declare i64  @nurl_sqlite_step(i64)` )
    ( emit `declare i64  @nurl_sqlite_column_count(i64)` )
    ( emit `declare i64  @nurl_sqlite_column_type(i64, i64)` )
    ( emit `declare i64  @nurl_sqlite_column_int(i64, i64)` )
    ( emit `declare i8*  @nurl_sqlite_column_text(i64, i64)` )
    ( emit `declare void @nurl_sqlite_finalize(i64)` )
    ( emit `declare i64  @nurl_sqlite_reset(i64)` )
    ( emit `` )
}

// ── Pre-register runtime functions returning i8* ──────────────────

// Normalise an import-path string so the dedup logic treats `./x` and
// `x` as the same file. Strips one or more leading "./" segments. We
// deliberately do NOT call realpath — that would require a runtime FFI
// and exposes symlink / cwd quirks that are unlikely to matter in
// practice. The 99% case is a user typing `./stdlib/foo.nu` once and
// `stdlib/foo.nu` elsewhere in the same project; this catches it.
// Called at every `$`-import path read site (scan_generic_structs,
// scan_fn_sigs, gen_import_decl) so all three dedup tables key on the
// same canonical form.
@ __norm_import_path s path → s {
    : ~ s cur path
    : ~ b done F
    ~ ! done {
        : i n ( nurl_str_len cur )
        ? & >= n 2 & == ( nurl_str_get cur 0 ) 46 == ( nurl_str_get cur 1 ) 47
        { = cur ( nurl_str_slice cur 2 - n 2 ) }
        { = done T }
    }
    ^ cur
}

@ mem_is_imported i syms s path → b {
    : s list ( nurl_sym_get syms `__imported_files__` )
    ^ ( str_contains_word list path )
}

@ mem_mark_imported i syms s path → v {
    : s list ( nurl_sym_get syms `__imported_files__` )
    : s new ? == 0 ( nurl_str_len list )
    path
    ( nurl_str_cat3 list ` ` path )
    ( nurl_sym_def syms `__imported_files__` new )
}

@ init_syms i syms → v {
    ( nurl_sym_def syms `__imported_files__` `` )
    ( nurl_sym_def syms `__scanned_files__` `` )
    // i8*-returning runtime functions
    ( nurl_sym_def syms `nurl_lex_val` `i8*` )
    ( nurl_sym_def syms `nurl_lex_filename` `i8*` )
    ( nurl_sym_def syms `nurl_lex_line_text` `i8*` )
    ( nurl_sym_def syms `nurl_diag_caret` `i8*` )
    ( nurl_sym_def syms `nurl_cg_reg` `i8*` )
    ( nurl_sym_def syms `nurl_cg_lbl` `i8*` )
    ( nurl_sym_def syms `nurl_get_last_type` `i8*` )
    ( nurl_sym_def syms `nurl_sym_get` `i8*` )
    ( nurl_sym_def syms `nurl_argv` `i8*` )
    ( nurl_sym_def syms `nurl_argv_get` `i8*` )
    ( nurl_sym_def syms `nurl_read_file` `i8*` )
    ( nurl_sym_def syms `nurl_read_line` `i8*` )
    ( nurl_sym_def syms `nurl_read_n_bytes` `i8*` )
    // PURIFY.md Phase 5 Batches C+D' (2026-05-23): nurl_str_cat /
    // _cat3 / _cat4 / _slice / _str_int are pure-NURL @-fns now.
    // The sym_def keeps cross-module callers typed correctly even
    // when they don't `$`-import string.nu — omitting it makes
    // nurlc emit `call i64 @nurl_str_cat(...)` and the LLVM verifier
    // rejects the type mismatch. nurl_str_float (Batch D) still has
    // a C body.
    ( nurl_sym_def syms `nurl_str_cat` `i8*` )
    ( nurl_sym_def syms `nurl_str_cat3` `i8*` )
    ( nurl_sym_def syms `nurl_str_cat4` `i8*` )
    ( nurl_sym_def syms `nurl_str_int` `i8*` )
    ( nurl_sym_def syms `nurl_str_float` `i8*` )
    ( nurl_sym_def syms `nurl_str_slice` `i8*` )
    // Phase 2B: mark allocating string runtime calls as returning OWNED str.
    // Gated on g_auto_drop_strings — off by default to keep the compiler's
    // own source compilable without false-positive auto-drops. The sideband
    // `__ret_owned` carries kind: "1" = slice (Phase 2A), "str" = string.
    ? != 0 g_auto_drop_strings
    { ( nurl_sym_def syms `nurl_str_cat__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_cat3__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_cat4__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_int__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_float__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_slice__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_read_file__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_read_line__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_read_n_bytes__ret_owned` `str` )
    }
    {}
    ( nurl_sym_def syms `malloc` `i8*` )
    ( nurl_sym_def syms `nurl_malloc` `i8*` )
    ( nurl_sym_def syms `nurl_alloc` `i8*` )
    ( nurl_sym_def syms `nurl_zalloc` `i8*` )
    ( nurl_sym_def syms `nurl_realloc` `i8*` )
    // libc string / parse primitives (PURIFY.md Phase 5, 2026-05-23)
    ( nurl_sym_def syms `strlen` `i64` )
    ( nurl_sym_def syms `strcmp` `i32` )
    ( nurl_sym_def syms `strncmp` `i32` )
    ( nurl_sym_def syms `memcmp` `i32` )
    ( nurl_sym_def syms `strstr` `i8*` )
    ( nurl_sym_def syms `memmem` `i8*` )
    ( nurl_sym_def syms `atoll` `i64` )
    ( nurl_sym_def syms `atof` `double` )
    ( nurl_sym_def syms `strtod` `double` )
    ( nurl_sym_def syms `memcpy` `i8*` )
    ( nurl_sym_def syms `strdup` `i8*` )
    // libc stdio (PURIFY.md Phase 7, 2026-05-23) — i64-typed returns
    // align with how the @-fns capture them. fopen returns FILE*
    // (i8*); fread/fwrite return size_t which we treat as i64.
    ( nurl_sym_def syms `fopen` `i8*` )
    ( nurl_sym_def syms `fclose` `i32` )
    ( nurl_sym_def syms `fputs` `i32` )
    ( nurl_sym_def syms `fwrite` `i64` )
    ( nurl_sym_def syms `fputc` `i32` )
    ( nurl_sym_def syms `fread` `i64` )
    ( nurl_sym_def syms `feof` `i32` )
    ( nurl_sym_def syms `access` `i32` )
    // file I/O
    ( nurl_sym_def syms `nurl_file_open` `i8*` )
    ( nurl_sym_def syms `nurl_file_write` `void` )
    ( nurl_sym_def syms `nurl_file_write_range` `void` )
    ( nurl_sym_def syms `nurl_file_write_byte` `void` )
    ( nurl_sym_def syms `nurl_file_close` `void` )
    ( nurl_sym_def syms `nurl_file_read` `i8*` )
    ( nurl_sym_def syms `nurl_file_exists` `i64` )
    ( nurl_sym_def syms `nurl_file_size` `i64` )
    ( nurl_sym_def syms `nurl_file_del` `void` )
    // non-fatal fs API used by stdlib/std/fs.nu — raw is an i8* the caller
    // must `nurl_free` after copying (see read_file). Intentionally NOT
    // marked __ret_owned to avoid double-free against the manual free.
    ( nurl_sym_def syms `nurl_read_file_safe` `i8*` )
    ( nurl_sym_def syms `nurl_read_file_mmap` `i8*` )
    ( nurl_sym_def syms `nurl_write_file_safe` `i64` )
    ( nurl_sym_def syms `nurl_dir_create` `i64` )
    ( nurl_sym_def syms `nurl_dir_remove` `i64` )
    ( nurl_sym_def syms `nurl_errno_kind` `i64` )
    // double-returning runtime functions
    ( nurl_sym_def syms `nurl_lex_fnum` `double` )
    ( nurl_sym_def syms `nurl_str_float_value` `double` )
    ( nurl_sym_def syms `nurl_parse_float_range` `double` )
    // libm wrappers + iabs/ipow removed in PURIFY.md Phase 3 — see
    // `stdlib/std/float.nu` (libm FFI) and `stdlib/std/int.nu`
    // (pure-NURL int_abs / int_pow).
    // i64-returning math/parse helpers (still C-side)
    ( nurl_sym_def syms `nurl_is_nan` `i64` )
    ( nurl_sym_def syms `nurl_is_inf` `i64` )
    ( nurl_sym_def syms `nurl_str_to_float_safe` `i64` )
    ( nurl_sym_def syms `nurl_parse_int_range` `i64` )
    // nurl_str_len / _eq / _cmp / _to_int / _to_float / _starts /
    // _find / _ends / _memmem_range / _memcmp_lex — pure-NURL
    // @-fns now (PURIFY.md Phase 5, 2026-05-23). Their return
    // types are discovered from the @-fn declaration itself.
    ( nurl_sym_def syms `nurl_csv_scan_cell` `i64` )
    ( nurl_sym_def syms `nurl_csv_filter_float_gt` `i64` )
    ( nurl_sym_def syms `nurl_csv_filter_str_contains` `i64` )
    ( nurl_sym_def syms `nurl_csv_filter_float_gt_and_str_contains` `i64` )
    ( nurl_sym_def syms `nurl_csv_filter_typed_float_gt` `i64` )
    ( nurl_sym_def syms `nurl_has_byte` `i64` )
    ( nurl_sym_def syms `nurl_count_byte` `i64` )
    ( nurl_sym_def syms `nurl_csv_fast_float_range` `double` )
    ( nurl_sym_def syms `nurl_csv_parse_arena` `i64` )
    ( nurl_sym_def syms `nurl_csv_n_rows_out` `i64` )
    ( nurl_sym_def syms `nurl_csv_n_header_out` `i64` )
    ( nurl_sym_def syms `nurl_csv_n_cells_out` `i64` )
    ( nurl_sym_def syms `nurl_csv_scan_row_pairs` `i64` )
    ( nurl_sym_def syms `nurl_csv_row_n_cells_out` `i64` )
    ( nurl_sym_def syms `nurl_csv_row_next_pos_out` `i64` )
    ( nurl_sym_def syms `nurl_now_ms` `i64` )
    ( nurl_sym_def syms `nurl_now_seconds` `i64` )
    ( nurl_sym_def syms `nurl_monotonic_ns` `i64` )
    ( nurl_sym_def syms `nurl_sleep_ms` `void` )
    // CLI tooling — i8*-returning calls return heap-owned strings (caller frees)
    ( nurl_sym_def syms `nurl_env_get` `i8*` )
    ( nurl_sym_def syms `nurl_cwd` `i8*` )
    ( nurl_sym_def syms `nurl_read_all_stdin` `i8*` )
    ( nurl_sym_def syms `nurl_dir_list_next` `i8*` )
    ( nurl_sym_def syms `nurl_env_set` `i64` )
    ( nurl_sym_def syms `nurl_env_unset` `i64` )
    ( nurl_sym_def syms `nurl_chdir` `i64` )
    ( nurl_sym_def syms `nurl_dir_list_open` `i64` )
    ( nurl_sym_def syms `nurl_dir_list_close` `void` )
    // HTTP runtime helpers (libcurl bridge — see runtime.c §14).
    // Body / header accessors return BORROWED i8* views into the
    // response struct, so they intentionally do NOT carry the
    // __ret_owned=str marker — the caller MUST NOT auto-free them.
    ( nurl_sym_def syms `nurl_http_perform_full` `i64` )
    ( nurl_sym_def syms `nurl_http_perform_full_to` `i64` )
    ( nurl_sym_def syms `nurl_http_response_status` `i64` )
    ( nurl_sym_def syms `nurl_http_response_err_kind` `i64` )
    ( nurl_sym_def syms `nurl_http_response_body` `i8*` )
    ( nurl_sym_def syms `nurl_http_response_body_len` `i64` )
    ( nurl_sym_def syms `nurl_http_response_header_count` `i64` )
    ( nurl_sym_def syms `nurl_http_response_header_name` `i8*` )
    ( nurl_sym_def syms `nurl_http_response_header_value` `i8*` )
    ( nurl_sym_def syms `nurl_http_response_free` `void` )
    // HTTP streaming (runtime.c §14b). Pull-based — NURL drives one
    // chunk at a time. `nurl_http_stream_next` returns a heap-owned
    // i8* (NULL on EOF/error); mark it as owned so auto-drop wraps it.
    ( nurl_sym_def syms `nurl_http_stream_open_to` `i64` )
    ( nurl_sym_def syms `nurl_http_stream_next` `i8*` )
    ( nurl_sym_def syms `nurl_http_stream_next__ret_owned` `str` )
    ( nurl_sym_def syms `nurl_http_stream_status` `i64` )
    ( nurl_sym_def syms `nurl_http_stream_err_kind` `i64` )
    ( nurl_sym_def syms `nurl_http_stream_close` `void` )
    ( nurl_sym_def syms `nurl_http_stream_pump_headers` `i64` )
    ( nurl_sym_def syms `nurl_http_stream_header_count` `i64` )
    ( nurl_sym_def syms `nurl_http_stream_header_name` `i8*` )
    ( nurl_sym_def syms `nurl_http_stream_header_value` `i8*` )
    // process execution (runtime §16). Output buffers are BORROWED views
    // into the runtime-owned NurlProcResult — do NOT mark __ret_owned.
    ( nurl_sym_def syms `nurl_proc_run` `i64` )
    ( nurl_sym_def syms `nurl_proc_exit_code` `i64` )
    ( nurl_sym_def syms `nurl_proc_err_kind` `i64` )
    ( nurl_sym_def syms `nurl_proc_stdout` `i8*` )
    ( nurl_sym_def syms `nurl_proc_stderr` `i8*` )
    ( nurl_sym_def syms `nurl_proc_stdout_len` `i64` )
    ( nurl_sym_def syms `nurl_proc_stderr_len` `i64` )
    ( nurl_sym_def syms `nurl_proc_free` `void` )
    // process spawn / duplex stdio (runtime §16b). read_line returns a
    // BORROWED i8* view into the child's internal line buffer (reused on
    // the next call) — do NOT mark __ret_owned. Callers copy via
    // string_from to materialise an owned String.
    ( nurl_sym_def syms `nurl_proc_spawn` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_err_kind` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_pid` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_write` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_close_stdin` `void` )
    ( nurl_sym_def syms `nurl_proc_spawn_read_line` `i8*` )
    ( nurl_sym_def syms `nurl_proc_spawn_read_line_len` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_eof` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_last_io_err` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_wait` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_kill` `i64` )
    ( nurl_sym_def syms `nurl_proc_spawn_free` `void` )
    // crypto (runtime §17). The hex-digest returns are heap-owned i8*
    // (caller frees via nurl_free); not auto-marked __ret_owned because
    // the wrappers in stdlib/std/hash.nu and stdlib/std/random.nu do
    // their own copy + free.
    // Crypto hash sym_defs — see PURIFY.md Phase 4 comment above.
    ( nurl_sym_def syms `nurl_rand_u64` `i64` )
    ( nurl_sym_def syms `nurl_rand_bytes_hex` `i8*` )
    // Binary file I/O (runtime §4 extension). Read returns a heap buffer +
    // sideband length via nurl_last_bytes_len; not __ret_owned-marked
    // because stdlib/std/fs.nu reads the bytes into a Vec[u] and frees
    // the buffer manually.
    ( nurl_sym_def syms `nurl_read_file_bytes` `i8*` )
    ( nurl_sym_def syms `nurl_write_file_bytes` `i64` )
    ( nurl_sym_def syms `nurl_last_bytes_len` `i64` )
    // TCP sockets (runtime §18). Handles are i64-cast heap pointers; the
    // peer-addr accessor returns a BORROWED view into the handle struct,
    // so it is intentionally NOT __ret_owned-marked (caller copies via
    // string_from when a long-lived String is required).
    ( nurl_sym_def syms `nurl_tcp_listen` `i64` )
    ( nurl_sym_def syms `nurl_tcp_listen_tls` `i64` )
    ( nurl_sym_def syms `nurl_tcp_listen_tls_alpn` `i64` )
    ( nurl_sym_def syms `nurl_tcp_alpn_selected` `i8*` )
    ( nurl_sym_def syms `nurl_tcp_tls_add_sni` `i64` )
    ( nurl_sym_def syms `nurl_tcp_tls_reload` `i64` )
    ( nurl_sym_def syms `nurl_tcp_tls_require_client_cert` `i64` )
    ( nurl_sym_def syms `nurl_tcp_peer_cert_subject` `i8*` )
    ( nurl_sym_def syms `nurl_dos_state_new` `i64` )
    ( nurl_sym_def syms `nurl_dos_state_try_acquire` `i64` )
    ( nurl_sym_def syms `nurl_dos_state_release` `void` )
    ( nurl_sym_def syms `nurl_dos_state_free` `void` )
    ( nurl_sym_def syms `nurl_dos_state_active` `i64` )
    ( nurl_sym_def syms `nurl_tcp_accept` `i64` )
    ( nurl_sym_def syms `nurl_tcp_read` `i64` )
    ( nurl_sym_def syms `nurl_tcp_write` `i64` )
    ( nurl_sym_def syms `nurl_tcp_close` `void` )
    ( nurl_sym_def syms `nurl_tcp_shutdown` `void` )
    ( nurl_sym_def syms `nurl_tcp_err_kind` `i64` )
    ( nurl_sym_def syms `nurl_tcp_peer_addr` `i8*` )
    ( nurl_sym_def syms `nurl_tcp_set_timeout` `void` )
    // Thread / mutex / cond entirely on the pure-NURL FFI side now
    // (PURIFY Phase 6): pthread_create / pthread_mutex_* /
    // pthread_cond_* plus the nurl_pthread_join_ptr / _detach_ptr
    // trampolines are declared in stdlib/std/thread.nu via `& `c` @ ...`,
    // so no sym_def registrations are needed here.
    ( nurl_sym_def syms `nurl_signal_install_shutdown` `void` )
    ( nurl_sym_def syms `nurl_signal_trigger_shutdown` `void` )
    ( nurl_sym_def syms `nurl_panic` `void` )
    ( nurl_sym_def syms `nurl_recover` `i64` )
    ( nurl_sym_def syms `nurl_panic_last_msg` `i8*` )
    ( nurl_sym_def syms `nurl_sqlite_open` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_close` `void` )
    ( nurl_sym_def syms `nurl_sqlite_err_kind` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_errmsg` `i8*` )
    ( nurl_sym_def syms `nurl_sqlite_exec` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_prepare` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_stmt_err_kind` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_bind_int` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_bind_text` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_bind_null` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_step` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_column_count` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_column_type` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_column_int` `i64` )
    ( nurl_sym_def syms `nurl_sqlite_column_text` `i8*` )
    ( nurl_sym_def syms `nurl_sqlite_finalize` `void` )
    ( nurl_sym_def syms `nurl_sqlite_reset` `i64` )
    // void runtime functions
    ( nurl_sym_def syms `nurl_print` `void` )
    ( nurl_sym_def syms `nurl_eprint` `void` )
    ( nurl_sym_def syms `nurl_eprintln` `void` )
    ( nurl_sym_def syms `nurl_print_int` `void` )
    ( nurl_sym_def syms `nurl_print_str` `void` )
    ( nurl_sym_def syms `nurl_print_bool` `void` )
    ( nurl_sym_def syms `nurl_lex_advance` `void` )
    ( nurl_sym_def syms `nurl_sym_def` `void` )
    ( nurl_sym_def syms `nurl_sym_push` `void` )
    ( nurl_sym_def syms `nurl_sym_pop` `void` )
    ( nurl_sym_def syms `nurl_cg_reset` `void` )
    ( nurl_sym_def syms `nurl_set_last_type` `void` )
    ( nurl_sym_def syms `nurl_exit` `void` )
    ( nurl_sym_def syms `nurl_flush_stdout` `void` )
    ( nurl_sym_def syms `nurl_flush_stderr` `void` )
    ( nurl_sym_def syms `nurl_stdin_eof` `i64` )
    ( nurl_sym_def syms `free` `void` )
    ( nurl_sym_def syms `nurl_free` `void` )
    ( nurl_sym_def syms `nurl_map_put` `void` )
    ( nurl_sym_def syms `nurl_map_del` `void` )
    ( nurl_sym_def syms `nurl_map_free` `void` )
    ( nurl_sym_def syms `nurl_memcpy` `void` )
    ( nurl_sym_def syms `nurl_poke` `void` )
    // output buffering
    ( nurl_sym_def syms `nurl_print_buf_start` `void` )
    ( nurl_sym_def syms `nurl_print_buf_stop` `i8*` )
    ( nurl_sym_def syms `nurl_print_buf_reset` `void` )
    // lexer position save/restore
    ( nurl_sym_def syms `nurl_lex_cur_start` `i64` )
    ( nurl_sym_def syms `nurl_lex_src_slice` `i8*` )
    ( nurl_sym_def syms `nurl_lex_set_pos` `void` )
}

// ── Signature pre-scan (first pass) ──────────────────────────────

// skip_balanced: skip a balanced { ... } block from the lexer.
// Both loops guard against EOF so a malformed source (e.g. missing
// `→` in a function header, or an unclosed `{`) cannot park the
// compiler in an infinite loop.
@ skip_balanced i lex → v {
    ~ & != ( nurl_lex_type lex ) TT_LBRACE != ( nurl_lex_type lex ) TT_EOF
    { ( nurl_lex_advance lex ) }
    // Only descend into the body if we actually found a `{`. If we hit
    // EOF first (malformed source), fall through and let the caller
    // observe TT_EOF on its next step.
    ? == ( nurl_lex_type lex ) TT_LBRACE
    { ( nurl_lex_advance lex )
        : i depth 1
        ~ & != depth 0 != ( nurl_lex_type lex ) TT_EOF {
            : i tt2 ( nurl_lex_type lex )
            ? == tt2 TT_LBRACE { = depth + depth 1 } {}
            ? == tt2 TT_RBRACE { = depth - depth 1 } {}
            ( nurl_lex_advance lex )
        }
    }
    {}
}

// scan_trait_body: walk a trait's '{ ... }' block, storing default-method
// templates in g_trait_syms. Required methods (header-only) need no storage.
// Captures the raw source substring (including backticks and escape
// sequences) for each default method via nurl_lex_src_slice so the
// template can be re-lexed later even when the body uses string literals.
@ scan_trait_body i lex s tname → v {
    ( expect lex TT_LBRACE )
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        ? == ( nurl_lex_type lex ) TT_AT
        { ( nurl_lex_advance lex )  // skip '@'
            ? ( is_ident_tok ( nurl_lex_type lex ) )
            { : s mname ( nurl_lex_val lex )
                ( nurl_lex_advance lex )  // consume method name
                : i sig_start ( nurl_lex_cur_start lex )
                // Skip params / → / ret_ty until we hit '{' (body), next '@',
                // or '}' (end of trait).
                ~ & & != ( nurl_lex_type lex ) TT_LBRACE
                != ( nurl_lex_type lex ) TT_AT
                != ( nurl_lex_type lex ) TT_RBRACE {
                    ( nurl_lex_advance lex )
                }
                ? == ( nurl_lex_type lex ) TT_LBRACE
                {  // Default method: consume the body block and capture raw source.
                    ( skip_balanced lex )
                    : i end_pos ( nurl_lex_cur_start lex )
                    : s src ( nurl_lex_src_slice lex sig_start - end_pos sig_start )
                    ( nurl_sym_def g_trait_syms
                    ( nurl_str_cat tname ( nurl_str_cat `__` ( nurl_str_cat mname `__src` ) ) )
                    src )
                    : s defaults_key ( nurl_str_cat tname `__defaults` )
                    : s cur ( nurl_sym_get g_trait_syms defaults_key )
                    ( nurl_sym_def g_trait_syms defaults_key
                    ? == 0 ( nurl_str_len cur )
                    mname
                    ( nurl_str_cat cur ( nurl_str_cat ` ` mname ) ) )
                }
                {}  // header only — required method, no template to store
            }
            { ( nurl_lex_advance lex ) }
        }
        { ( nurl_lex_advance lex ) }
    }
    ( nurl_lex_advance lex )  // consume '}'
}

// trait_default_ret: given a default method's substituted source
// "params → ret { body }", return the ret type as an LLVM type string.
@ trait_default_ret s subst_src → s {
    : i lex2 ( nurl_lex_new subst_src `<trait_default_ret>` )
    ~ & != ( nurl_lex_type lex2 ) TT_ARROW != ( nurl_lex_type lex2 ) TT_EOF {
        ( nurl_lex_advance lex2 )
    }
    : s ret `i64`
    ? == ( nurl_lex_type lex2 ) TT_ARROW
    { ( nurl_lex_advance lex2 )
        = ret ( parse_type lex2 )
    }
    {}
    ret
}

// register_missing_defaults: for each of a trait's default methods that the
// impl did NOT override, register a dispatch entry (method##ImplLLVM →
// ret_ty) so that call sites resolve. Called during impl scan.
@ register_missing_defaults s tname s impl_nurl s impl_llvm s impl_mangle s provided i syms → v {
    : s tparam ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__tparam` ) )
    : s defaults ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__defaults` ) )
    ~ != 0 ( nurl_str_len defaults ) {
        : s mname ( str_first_word defaults )
        = defaults ( str_skip_word defaults )
        ? ( str_contains_word provided mname )
        {}  // explicitly overridden by impl
        { : s src ( nurl_sym_get g_trait_syms
            ( nurl_str_cat tname ( nurl_str_cat `__` ( nurl_str_cat mname `__src` ) ) ) )
            : s subst ? != 0 ( nurl_str_len tparam )
            ( subst_source_raw src tparam impl_nurl )
            src
            : s ret_ty ( trait_default_ret subst )
            : s key ( nurl_str_cat mname ( nurl_str_cat `##` impl_llvm ) )
            ( nurl_sym_def g_impl_ret_syms key ret_ty )
            ( nurl_sym_def g_impl_name_syms key impl_mangle )
            : s mangled ( nurl_str_cat mname ( nurl_str_cat `__` impl_mangle ) )
            ( nurl_sym_def syms mangled ret_ty )
        }
    }
}

// capture_impl_nurl_name: return the NURL-source form of the impl type
// at the current lex position (used for T → ImplType substitution).
// For simple IDENT / TYPE_KW types this is just the token value. More
// complex types (* T, [ T, ...) are not supported for trait defaults.
@ capture_impl_nurl_name i lex → s {
    : i tt ( nurl_lex_type lex )
    ? | ( is_ident_tok tt ) == tt TT_TYPE_KW
    ( nurl_lex_val lex )
    ``
}

// scan_impl_decl: pre-scan a % trait/impl declaration, registering impl methods.
// Registers in g_impl_ret_syms and g_impl_name_syms so gen_call can dispatch.
// For trait_decl: stores default-method templates in g_trait_syms.
// For impl_decl: after scanning explicit methods, fills in dispatch entries
// for any of the trait's defaults that the impl did not override.
@ scan_impl_decl i lex i syms → v {
    ( nurl_lex_advance lex )  // skip '%'
    : s tname ( nurl_lex_val lex )
    ( nurl_lex_advance lex )  // skip trait name
    // Capture optional type param [T]  (bare letter T lexes as TT_BOOL)
    : s tparam ``
    ? == ( nurl_lex_type lex ) TT_LBRACK
    { ( nurl_lex_advance lex )
        : i tpt ( nurl_lex_type lex )
        ? | ( is_ident_tok tpt ) == tpt TT_BOOL
        { = tparam ( nurl_lex_val lex ) }
        {}
        ~ != ( nurl_lex_type lex ) TT_RBRACK { ( nurl_lex_advance lex ) }
        ( nurl_lex_advance lex )  // ']'
    }
    {}
    // Disambiguate: '{' → trait_decl, else → impl_decl
    ? == ( nurl_lex_type lex ) TT_LBRACE
    {  // trait: remember its type param and scan for default methods
        ( nurl_sym_def g_trait_syms ( nurl_str_cat tname `__tparam` ) tparam )
        ( scan_trait_body lex tname )
    }
    {  // impl_decl: read implementing type, then scan methods
        : s impl_nurl ( capture_impl_nurl_name lex )
        : s impl_llvm ( parse_type lex )  // e.g. "i64", "i8*", "%Point"
        : s impl_mangle ( mangle_type impl_llvm )
        ( expect lex TT_LBRACE )
        : s provided ``
        ~ != ( nurl_lex_type lex ) TT_RBRACE {
            ? == ( nurl_lex_type lex ) TT_AT
            { ( nurl_lex_advance lex )  // skip '@'
                ? ( is_ident_tok ( nurl_lex_type lex ) )
                { : s mname ( nurl_lex_val lex )
                    ( nurl_lex_advance lex )  // skip method name
                    = provided ? == 0 ( nurl_str_len provided )
                    mname
                    ( nurl_str_cat provided ( nurl_str_cat ` ` mname ) )
                    // Skip params until →
                    ~ & != ( nurl_lex_type lex ) TT_ARROW
                    != ( nurl_lex_type lex ) TT_EOF
                    { ( nurl_lex_advance lex ) }
                    ? == ( nurl_lex_type lex ) TT_ARROW
                    { ( nurl_lex_advance lex )
                        : s ret_ty ( parse_type lex )
                        : s key ( nurl_str_cat mname ( nurl_str_cat `##` impl_llvm ) )
                        ( nurl_sym_def g_impl_ret_syms key ret_ty )
                        ( nurl_sym_def g_impl_name_syms key impl_mangle )
                        : s mangled ( nurl_str_cat mname ( nurl_str_cat `__` impl_mangle ) )
                        ( nurl_sym_def syms mangled ret_ty )
                    }
                    {}
                    ( skip_balanced lex )  // skip method body
                }
                { ( nurl_lex_advance lex ) }
            }
            { ( nurl_lex_advance lex ) }
        }
        ( nurl_lex_advance lex )  // consume '}'
        // After the impl's explicit methods, synthesize dispatch entries for
        // any of the trait's defaults that this impl did not override.
        ? != 0 ( nurl_str_len impl_nurl )
        { ( register_missing_defaults tname impl_nurl impl_llvm impl_mangle provided syms ) }
        {}
    }
}

// emit_missing_defaults: for each trait default not overridden by the impl,
// splice "T" → impl's NURL type name into the stored template, prepend
// "@ mname__ImplMangle", and re-lex/emit via gen_fn_decl.
@ emit_missing_defaults s tname s impl_nurl s impl_mangle s provided i syms i cg → v {
    : s tparam ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__tparam` ) )
    : s defaults ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__defaults` ) )
    ~ != 0 ( nurl_str_len defaults ) {
        : s mname ( str_first_word defaults )
        = defaults ( str_skip_word defaults )
        ? ( str_contains_word provided mname )
        {}  // overridden: impl's concrete method already emitted
        { : s src ( nurl_sym_get g_trait_syms
            ( nurl_str_cat tname ( nurl_str_cat `__` ( nurl_str_cat mname `__src` ) ) ) )
            : s subst ? != 0 ( nurl_str_len tparam )
            ( subst_source_raw src tparam impl_nurl )
            src
            : s mangled ( nurl_str_cat mname ( nurl_str_cat `__` impl_mangle ) )
            : s full_src ( nurl_str_cat `@ ` ( nurl_str_cat mangled ( nurl_str_cat ` ` subst ) ) )
            : i lex2 ( nurl_lex_new full_src `<trait_default>` )
            ( gen_fn_decl lex2 syms cg )
        }
    }
}

// gen_trait_or_impl: emit IR for a % trait/impl declaration.
// Trait decls emit no IR directly. Impl decls emit explicit methods and then
// synthesize specialised copies of any trait default methods the impl omitted.
@ gen_trait_or_impl i lex i syms i cg → v {
    // Grammar v2.0+: `pub` on trait/impl decls is accepted (forward-
    // compat) but not yet enforced — trait methods are mangled at
    // emission so cross-file dispatch is type-driven, not name-
    // driven. v2 may revisit if there's a real interop case.
    ( vis_take_pending_pub )
    ( nurl_lex_advance lex )  // skip '%'
    : s tname ( nurl_lex_val lex )
    ( nurl_lex_advance lex )  // skip trait name
    // Skip optional type params [T] (already captured during scan)
    ? == ( nurl_lex_type lex ) TT_LBRACK
    { ( nurl_lex_advance lex )
        ~ != ( nurl_lex_type lex ) TT_RBRACK { ( nurl_lex_advance lex ) }
        ( nurl_lex_advance lex )  // ']'
    }
    {}
    // Disambiguate: '{' → trait_decl (no IR), else → impl_decl
    ? == ( nurl_lex_type lex ) TT_LBRACE
    { ( skip_balanced lex ) }  // trait: skip whole block, no IR
    {  // impl_decl: read implementing type, emit methods with mangled names
        : s impl_nurl ( capture_impl_nurl_name lex )
        : s impl_llvm ( parse_type lex )
        : s impl_mangle ( mangle_type impl_llvm )
        ( expect lex TT_LBRACE )
        : s provided ``
        ~ != ( nurl_lex_type lex ) TT_RBRACE {
            ? == ( nurl_lex_type lex ) TT_AT
            { ( nurl_lex_advance lex )  // skip '@'
                ? ( is_ident_tok ( nurl_lex_type lex ) )
                { : s mname ( nurl_lex_val lex )
                    ( nurl_lex_advance lex )  // skip method name
                    = provided ? == 0 ( nurl_str_len provided )
                    mname
                    ( nurl_str_cat provided ( nurl_str_cat ` ` mname ) )
                    : s mangled ( nurl_str_cat mname ( nurl_str_cat `__` impl_mangle ) )
                    // gen_fn_decl_concrete reads params, →, ret, body from lex
                    ( gen_fn_decl_concrete mangled lex syms cg )
                }
                { ( die lex `expected method name in impl` ) }
            }
            { ( nurl_lex_advance lex ) }
        }
        ( nurl_lex_advance lex )  // consume '}'
        // Synthesize trait-default copies for any method the impl omitted.
        ? != 0 ( nurl_str_len impl_nurl )
        { ( emit_missing_defaults tname impl_nurl impl_mangle provided syms cg ) }
        {}
    }
}

// scan_compound_ta_inner: lex is positioned on TT_LPAREN of a compound
// type-arg `( Name T1 T2 ... )`. Consumes through the matching ')',
// recursively handling nested compound ta's, and returns the mangled
// fragment (`Name__T1__T2`, no leading `%`) for use as a single
// ta_list element by the caller. Triggers `ensure_struct_instantiated`
// for the inner generic so the LLVM `%Name__...` named type is emitted
// before the outer instantiation references it.
@ scan_compound_ta_inner i lex i syms → s {
    ( nurl_lex_advance lex )  // consume '('
    : s sname ( nurl_lex_val lex )
    ( nurl_lex_advance lex )  // consume Name
    : s ta_list ``
    : s mangle_sfx ``
    ~ & != ( nurl_lex_type lex ) TT_RPAREN != ( nurl_lex_type lex ) TT_EOF {
        : ~ s ta_word ``
        : ~ s ta_lty ``
        ? == ( nurl_lex_type lex ) TT_LPAREN
        { : s inner ( scan_compound_ta_inner lex syms )
            = ta_word inner
            = ta_lty ( nurl_str_cat `%` inner )
        }
        { = ta_word ( nurl_lex_val lex )
            ( nurl_lex_advance lex )
            = ta_lty ( llvm_type ta_word )
        }
        = ta_list ? == 0 ( nurl_str_len ta_list )
        ta_word
        ( nurl_str_cat3 ta_list ` ` ta_word )
        = mangle_sfx ( nurl_str_cat mangle_sfx
        ( nurl_str_cat `__` ( mangle_type ta_lty ) ) )
    }
    ? == ( nurl_lex_type lex ) TT_RPAREN { ( nurl_lex_advance lex ) } {}
    : s tparams ( nurl_sym_get g_generic_struct_syms ( nurl_str_cat sname `__stparams` ) )
    ? != 0 ( nurl_str_len tparams ) {
        ( ensure_struct_instantiated syms sname ta_list )
    } {}
    ^ ( nurl_str_cat sname mangle_sfx )
}

// scan_generic_structs: linear pre-pass that
//   (a) stores generic struct templates `: Name [T+] { ... }` in
//       g_generic_struct_syms, and
//   (b) for every `( Name T1 T2 ... )` occurrence — whether at type
//       position in a signature or mid-function-body — emits the
//       corresponding `%Name__T1[__T2] = type { ... }` named type and
//       registers its field metadata in `syms`.
//
// Must run AFTER emit_header (its output lands in the IR stream) and
// BEFORE scan_fn_sigs / parse_program (so signatures and bodies see
// the instantiated types). Nested generics in substituted field types
// are out of scope for this iteration — keep field types scalar or
// pointer-to-scalar.
@ scan_generic_structs i lex i syms → v {
    ~ != ( nurl_lex_type lex ) TT_EOF {
        : i tt ( nurl_lex_type lex )
        : ~ b handled F

        // (a) Generic struct declaration: `: ~? IDENT [ tparams ] { body }`.
        // We advance past `:` up front; mark `handled` immediately so the
        // outer-loop fallthrough advance does not over-consume the next
        // token. The only thing the fallthrough would have given us is
        // `:`-alignment, which we have already achieved.
        ? == tt TT_COLON {
            ( nurl_lex_advance lex )
            = handled T
            ? == ( nurl_lex_type lex ) TT_TILDE { ( nurl_lex_advance lex ) } {}
            ? ( is_ident_tok ( nurl_lex_type lex ) ) {
                : s sname ( nurl_lex_val lex )
                ( nurl_lex_advance lex )
                ? == ( nurl_lex_type lex ) TT_LBRACK {
                    ( nurl_lex_advance lex )
                    : s tparams ``
                    ~ & != ( nurl_lex_type lex ) TT_RBRACK != ( nurl_lex_type lex ) TT_EOF {
                        : s tp ( nurl_lex_val lex )
                        ( nurl_lex_advance lex )
                        = tparams ? == 0 ( nurl_str_len tparams ) tp
                        ( nurl_str_cat tparams ( nurl_str_cat ` ` tp ) )
                    }
                    ? == ( nurl_lex_type lex ) TT_RBRACK { ( nurl_lex_advance lex ) } {}
                    ? == ( nurl_lex_type lex ) TT_LBRACE {
                        : s body ( collect_fn_body lex )
                        ( nurl_sym_def g_generic_struct_syms ( nurl_str_cat sname `__stparams` ) tparams )
                        ( nurl_sym_def g_generic_struct_syms ( nurl_str_cat sname `__sbody` ) body )
                    } {}
                } {}
            } {}
        } {}

        // (b) Generic struct instantiation: `( Name T1 T2 ... )`.
        // Compound type-args `( Vec ( Pair K V ) )` recurse via
        // `scan_compound_ta_inner` so the inner instantiation is emitted
        // first and contributes a single mangled token (`Pair__str__i64`)
        // to the outer ta_list — keeping `ensure_struct_instantiated`'s
        // word-at-a-time walker simple.
        ? & ! handled == tt TT_LPAREN {
            ? == ( nurl_lex_peek_type lex ) TT_IDENT {
                ( nurl_lex_advance lex )  // past '('
                : s cand ( nurl_lex_val lex )
                : s tparams ( nurl_sym_get g_generic_struct_syms ( nurl_str_cat cand `__stparams` ) )
                ? != 0 ( nurl_str_len tparams ) {
                    ( nurl_lex_advance lex )  // past cand ident
                    : s ta_list ``
                    ~ & != ( nurl_lex_type lex ) TT_RPAREN != ( nurl_lex_type lex ) TT_EOF {
                        : ~ s ta ``
                        ? == ( nurl_lex_type lex ) TT_LPAREN
                        { = ta ( scan_compound_ta_inner lex syms ) }
                        { = ta ( nurl_lex_val lex )
                            ( nurl_lex_advance lex )
                        }
                        = ta_list ? == 0 ( nurl_str_len ta_list ) ta
                        ( nurl_str_cat ta_list ( nurl_str_cat ` ` ta ) )
                    }
                    ? == ( nurl_lex_type lex ) TT_RPAREN { ( nurl_lex_advance lex ) } {}
                    ( ensure_struct_instantiated syms cand ta_list )
                    = handled T
                } {}
            } {}
        } {}

        // Follow $ imports (same dedup list as scan_fn_sigs, kept separate
        // here so the ordering of the two scans doesn't matter).
        ? & ! handled == tt TT_DOLLAR {
            ( nurl_lex_advance lex )
            ? == ( nurl_lex_type lex ) TT_STR {
                : s path ( __norm_import_path ( nurl_lex_val lex ) )
                ( nurl_lex_advance lex )
                ? ( is_ident_tok ( nurl_lex_type lex ) ) { ( nurl_lex_advance lex ) } {}
                : s marker ( nurl_sym_get g_generic_struct_syms `__scanned__` )
                ? ( str_contains_word marker path ) {} {
                    : s new_marker ? == 0 ( nurl_str_len marker ) path
                    ( nurl_str_cat3 marker ` ` path )
                    ( nurl_sym_def g_generic_struct_syms `__scanned__` new_marker )
                    : s src2 ( nurl_read_file path )
                    : i lex2 ( nurl_lex_new src2 path )
                    ( scan_generic_structs lex2 syms )
                }
                = handled T
            } {}
        } {}

        ? ! handled { ( nurl_lex_advance lex ) } {}
    }
}

// __is_param_marker_word — true for the contextual parameter-convention
// keywords (`in` / `inout` / `sink`) that may lead a parameter. Mirrors
// parse_param_marker so the lexical param count below matches the real
// parser's view of where a parameter's type begins.
@ __is_param_marker_word s v → b {
    | | ( seq v `in` ) ( seq v `inout` ) ( seq v `sink` )
}

// scan_skip_paren — lexically advance past one balanced `( ... )` group.
// Returns 1 on a matched group, 0 if it ran into EOF first.
@ scan_skip_paren i lex → i {
    ? != ( nurl_lex_type lex ) TT_LPAREN { ^ 0 } {}
    ( nurl_lex_advance lex )
    : i depth 1
    ~ & != depth 0 != ( nurl_lex_type lex ) TT_EOF {
        : i t2 ( nurl_lex_type lex )
        ? == t2 TT_LPAREN { = depth + depth 1 } {}
        ? == t2 TT_RPAREN { = depth - depth 1 } {}
        ( nurl_lex_advance lex )
    }
    ? == depth 0 1 0
}

// scan_skip_type — lexically advance past ONE type expression in a
// function-signature parameter region. Mirrors parse_type's grammar
// shape but emits no IR and calls no parse_* helper: a parse_type call
// inside scan_fn_sigs desyncs the scan (BORROW.md Phase 4). Returns 1
// on success, 0 on a shape it cannot classify (an anonymous enum type,
// say); the caller then abandons the arity count for that function —
// a missed check, never a wrong one.
@ scan_skip_type i lex → i {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_STAR   { ( nurl_lex_advance lex ) ^ ( scan_skip_type lex ) } {}
    ? == tt TT_QUEST  { ( nurl_lex_advance lex ) ^ ( scan_skip_type lex ) } {}
    ? == tt TT_LBRACK { ( nurl_lex_advance lex ) ^ ( scan_skip_type lex ) } {}
    ? == tt TT_BANG
    { ( nurl_lex_advance lex )
        ? == 0 ( scan_skip_type lex ) { ^ 0 } {}
        ^ ( scan_skip_type lex ) }
    {}
    ? == tt TT_LPAREN { ^ ( scan_skip_paren lex ) } {}
    ? ( is_ident_tok tt ) { ( nurl_lex_advance lex ) ^ 1 } {}
    0
}

// scan_fn_sigs: register return types of all @ and & declarations.
@ scan_fn_sigs i lex i syms → v {
    ~ != ( nurl_lex_type lex ) TT_EOF {
        // Grammar v2.0: a top-level decl may be prefixed by `pub` to
        // mark it public. The flag is recorded in g_pending_pub and
        // consumed by vis_record_fn / vis_take_pending_pub at the
        // matching @-decl. Pre-step BEFORE reading tt so the dispatch
        // ternary chain below sees the post-pub token.
        ? == ( nurl_lex_type lex ) TT_PUB
        { ( nurl_lex_advance lex )
            = g_pending_pub 1
        }
        {}
        : i tt ( nurl_lex_type lex )
        ? == tt TT_AT
        { ( nurl_lex_advance lex )
            ? ( is_ident_tok ( nurl_lex_type lex ) )
            { : s fname ( nurl_lex_val lex )
                ( nurl_lex_advance lex )
                // Grammar v2.0: record per-fn source-file origin and (if the
                // preceding token was `pub`) the public flag. Strict-mode for
                // the current file flips to "1" the first time a pub @ is
                // seen, which gen_call later consults to enforce visibility.
                ( vis_record_fn fname ( vis_take_pending_pub ) )
                // Generic function [T U ...]: skip type params, mark as generic.
                // Slice type param [type name]: treat like regular params (not generic).
                // Must match the disambiguation in gen_fn_decl: accept IDENT *or*
                // BOOL for the param name (the bare letter `T` lexes as TT_BOOL),
                // and require ']' immediately after 1 or 2 param names.
                : b at_lbrack == ( nurl_lex_type lex ) TT_LBRACK
                : i p1s ? at_lbrack ( nurl_lex_peek_type lex ) 0
                : i p2s ? at_lbrack ( nurl_lex_peek2_type lex ) 0
                : i p3s ? at_lbrack ( nurl_lex_peek3_type lex ) 0
                : b n1s | == p1s TT_IDENT == p1s TT_BOOL
                : b n2s | == p2s TT_IDENT == p2s TT_BOOL
                : b n3s | == p3s TT_IDENT == p3s TT_BOOL
                : b gen1s & n1s == p2s TT_RBRACK
                : b gen2s & & n1s n2s == p3s TT_RBRACK
                : i p4s ? & at_lbrack & & n1s n2s n3s ( nurl_lex_peek4_type lex ) 0
                : b gen3s & & & n1s n2s n3s == p4s TT_RBRACK
                ? & at_lbrack | | gen1s gen2s gen3s
                { ~ != ( nurl_lex_type lex ) TT_RBRACK { ( nurl_lex_advance lex ) }
                    ( nurl_lex_advance lex )  // consume ']'
                    ( nurl_sym_def syms ( nurl_str_cat fname `__generic` ) `1` )
                    // BORROW.md Phase 4: scan the parameter region (from
                    // here to the body `{`) for the `inout` marker, just
                    // as the non-generic branch below does. `inout` is
                    // banned as a parameter NAME so a bare `inout` token
                    // here is exact. This lets a forward call to a
                    // generic `inout` function be rejected cleanly — the
                    // index set itself is computed by
                    // compute_generic_inout_sink at gen_generic_fn_store.
                    : ~ b g_saw_inout F
                    ~ & != ( nurl_lex_type lex ) TT_LBRACE != ( nurl_lex_type lex ) TT_EOF
                    { ? & ( is_ident_tok ( nurl_lex_type lex ) )
                          ( seq ( nurl_lex_val lex ) `inout` )
                        { = g_saw_inout T }
                        {}
                        ( nurl_lex_advance lex ) }
                    ? g_saw_inout
                    { ( nurl_sym_def syms ( nurl_str_cat fname `__has_inout` ) `1` ) }
                    {}
                    ( skip_balanced lex )
                }
                { // BORROW.md Phase 4 + arity: walk the parameter
                  // region counting parameters — one `[marker] TYPE
                  // NAME` triple each, the TYPE skipped purely
                  // lexically via scan_skip_type — and note whether the
                  // `inout` marker appears. `inout` is banned as a
                  // parameter NAME (see gen_fn_param) so a bare `inout`
                  // here is exact: `<fname>__has_inout` lets a forward
                  // call site reject calling an `inout` function before
                  // its definition is compiled. If the walk meets a
                  // shape scan_skip_type can't classify it abandons the
                  // count (pc_ok → F) and blind-advances the rest, so
                  // `<fname>__arity` is simply not recorded — a missed
                  // arity check, never a wrong one.
                    : ~ b saw_inout F
                    : ~ i pcount 0
                    : ~ b pc_ok T
                    ~ & & pc_ok != ( nurl_lex_type lex ) TT_ARROW
                          != ( nurl_lex_type lex ) TT_EOF
                    { ? & ( is_ident_tok ( nurl_lex_type lex ) )
                          ( __is_param_marker_word ( nurl_lex_val lex ) )
                        { ? ( seq ( nurl_lex_val lex ) `inout` )
                            { = saw_inout T } {}
                            ( nurl_lex_advance lex ) }
                        {}
                        ? == 0 ( scan_skip_type lex )
                        { = pc_ok F }
                        { ? ( is_ident_tok ( nurl_lex_type lex ) )
                            { ( nurl_lex_advance lex ) = pcount + pcount 1 }
                            { = pc_ok F } } }
                    // If the count was abandoned mid-region, advance the
                    // rest blind so the `->` / ret-type handling still
                    // runs (the arity entry is just not written).
                    ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF
                    { ( nurl_lex_advance lex ) }
                    ? saw_inout
                    { ( nurl_sym_def syms ( nurl_str_cat fname `__has_inout` ) `1` ) }
                    {}
                    ? pc_ok
                    { : s ar_key ( nurl_str_cat fname `__arity` )
                        : s ar_prev ( nurl_sym_get syms ar_key )
                        : s ar_new ( nurl_str_int pcount )
                        // Two definitions of the same name with
                        // different parameter counts (a latent stdlib
                        // collision) — neither arity can be trusted at
                        // a call site, so mark it ambiguous (`?`) and
                        // let gen_call skip the check rather than
                        // blame an innocent call.
                        ? & != 0 ( nurl_str_len ar_prev ) ! ( seq ar_prev ar_new )
                        { ( nurl_sym_def syms ar_key `?` ) }
                        { ( nurl_sym_def syms ar_key ar_new ) } }
                    {}
                    ? == ( nurl_lex_type lex ) TT_ARROW
                    { ( nurl_lex_advance lex )
                        : s ret_ty ( parse_type lex )
                        ( nurl_sym_def syms fname ret_ty )
                    }
                    {}
                    ( skip_balanced lex )
                }
            }
            { ( skip_balanced lex ) }
        }
        // import_decl: $ `path` alias?  — scan the imported file too
        ? == tt TT_DOLLAR
        { ( nurl_lex_advance lex )  // skip '$'
            : s path ( __norm_import_path ( nurl_lex_val lex ) )
            ( nurl_lex_advance lex )  // skip path STR
            : s alias ``
            ? ( is_ident_tok ( nurl_lex_type lex ) )
            { = alias ( nurl_lex_val lex )
                ( nurl_lex_advance lex )
            }
            {}
            : s scanned ( nurl_sym_get syms `__scanned_files__` )
            ? ( str_contains_word scanned path )
            {}
            { : s new_scanned ? == 0 ( nurl_str_len scanned )
                path
                ( nurl_str_cat3 scanned ` ` path )
                ( nurl_sym_def syms `__scanned_files__` new_scanned )
                : s src2 ( nurl_read_file path )
                : s eff_src2 ? != 0 ( nurl_str_len alias )
                { : s names ( collect_alias_targets src2 path )
                    ( alias_rewrite_source src2 names ( nurl_str_cat alias `__` ) )
                }
                src2
                : i lex2 ( nurl_lex_new eff_src2 path )
                // Save / restore the current source-file across the nested
                // scan so vis_record_fn attributes decls in the imported
                // file to that file's path, not the importer's.
                : s saved_sf ( vis_current_src_file )
                ( vis_set_current_src_file path )
                ( scan_fn_sigs lex2 syms )
                ( vis_set_current_src_file saved_sf )
            }
        }

        // ffi_decl: & STR @ name params → type  (no body block to skip)
        ? == tt TT_AMP
        { ( nurl_lex_advance lex )  // skip '&'
            ( nurl_lex_advance lex )  // skip library STR
            ( nurl_lex_advance lex )  // skip '@'
            ? ( is_ident_tok ( nurl_lex_type lex ) )
            { : s fname ( nurl_lex_val lex )
                ( nurl_lex_advance lex )
                ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF
                { ( nurl_lex_advance lex ) }
                ? == ( nurl_lex_type lex ) TT_ARROW
                { ( nurl_lex_advance lex )
                    : s ret_ty ( parse_type lex )
                    ( nurl_sym_def syms fname ret_ty )
                }
                {}
            }
            {}
        }
        { ? == tt TT_PERCENT
            { ( scan_impl_decl lex syms ) }
            { ( nurl_lex_advance lex ) }
        }
    }
}

// scan_type_names: linear pre-pass that registers every top-level type
// NAME into `syms` as `Name → %Name` — struct `: Name { ... }`, generic
// struct `: Name [T+] { ... }`, and enum `: | Name { ... }` — and
// follows `$`-imports. Runs before parse_program so gen_enum_decl's
// could_be_payload_type can recognise a struct/enum used as a variant
// payload even when that type is declared LATER in the file (a forward
// reference). Without it a forward-referenced payload type is misparsed
// as a phantom extra variant.
//
// Purely lexical + brace-depth-tracked — no parse_type call (the
// scan_fn_sigs param-walk desync lesson, BORROW.md Phase 4). Only
// depth-0 `:` decls are inspected; variant names live inside the `{}`
// body at depth > 0 and are never registered here. A constant
// (`: ~? Type name value`) carries its name in 2nd position with no
// `{`/`[` after the 1st token, so it is correctly skipped.
@ scan_type_names i lex i syms → v {
    : ~ i depth 0
    ~ != ( nurl_lex_type lex ) TT_EOF {
        : i tt ( nurl_lex_type lex )
        ? == tt TT_LBRACE
        { = depth + depth 1 ( nurl_lex_advance lex ) }
        { ? == tt TT_RBRACE
            { = depth - depth 1 ( nurl_lex_advance lex ) }
            { ? & == depth 0 == tt TT_DOLLAR
                {  // Nested import: register its type names too, applying
                   // alias rewriting so an aliased import's types resolve
                   // under their `alias__` prefix (mirrors scan_fn_sigs).
                    ( nurl_lex_advance lex )
                    ? == ( nurl_lex_type lex ) TT_STR
                    { : s path ( __norm_import_path ( nurl_lex_val lex ) )
                        ( nurl_lex_advance lex )
                        : ~ s alias ``
                        ? ( is_ident_tok ( nurl_lex_type lex ) )
                        { = alias ( nurl_lex_val lex ) ( nurl_lex_advance lex ) }
                        {}
                        : s marker ( nurl_sym_get syms `__tn_scanned__` )
                        ? ( str_contains_word marker path )
                        {}
                        { : s new_marker ? == 0 ( nurl_str_len marker ) path
                            ( nurl_str_cat3 marker ` ` path )
                            ( nurl_sym_def syms `__tn_scanned__` new_marker )
                            : s src2 ( nurl_read_file path )
                            : s eff_src2 ? != 0 ( nurl_str_len alias )
                            { : s names ( collect_alias_targets src2 path )
                                ( alias_rewrite_source src2 names ( nurl_str_cat alias `__` ) )
                            }
                            src2
                            : i lex2 ( nurl_lex_new eff_src2 path )
                            ( scan_type_names lex2 syms )
                        }
                    }
                    {}
                }
                { ? & == depth 0 == tt TT_COLON
                    { ( nurl_lex_advance lex )  // consume ':'
                        ? == ( nurl_lex_type lex ) TT_TILDE { ( nurl_lex_advance lex ) } {}
                        ? == ( nurl_lex_type lex ) TT_PIPE
                        {  // enum `: | Name { ... }` — name follows the `|`
                            ( nurl_lex_advance lex )
                            ? == ( nurl_lex_type lex ) TT_IDENT
                            { ( nurl_sym_def syms ( nurl_lex_val lex )
                                ( nurl_str_cat `%` ( nurl_lex_val lex ) ) ) }
                            {}
                        }
                        {  // struct iff a pure IDENT is immediately followed
                           // by `{` (struct body) or `[` (generic params).
                            ? == ( nurl_lex_type lex ) TT_IDENT
                            { : i nxt ( nurl_lex_peek_type lex )
                                ? | == nxt TT_LBRACE == nxt TT_LBRACK
                                { ( nurl_sym_def syms ( nurl_lex_val lex )
                                    ( nurl_str_cat `%` ( nurl_lex_val lex ) ) ) }
                                {}
                            }
                            {}
                        }
                    }
                    { ( nurl_lex_advance lex ) }
                }
            }
        }
    }
}

// ── Top-level loop ─────────────────────────────────────────────────

@ parse_program i lex i syms i cg → v {
    ~ != ( nurl_lex_type lex ) TT_EOF {
        // Grammar v2.0: consume an optional `pub` visibility prefix
        // before dispatching to the matching decl handler. The pending
        // flag is read-and-cleared by vis_take_pending_pub at the @-
        // decl site (gen_fn_decl). Other decl kinds parse the prefix
        // for forward-compat but enforcement is fn-only in v2.0.
        ? == ( nurl_lex_type lex ) TT_PUB
        { ( nurl_lex_advance lex )
            = g_pending_pub 1
        }
        {}
        : i tt ( nurl_lex_type lex )
        ? == tt TT_AT { ( gen_fn_decl lex syms cg ) }
        ? == tt TT_COLON { ( gen_const_or_struct lex syms ) }
        ? == tt TT_AMP { ( gen_ffi_decl lex syms ) }
        ? == tt TT_DOLLAR { ( gen_import_decl lex syms cg ) }
        ? == tt TT_PERCENT { ( gen_trait_or_impl lex syms cg ) }
        { ( nurl_lex_advance lex ) }
    }
}

// ── Entry point ────────────────────────────────────────────────────

@ main → v {
    // CLI: `nurlc [--g] [--no-borrowck] <file.nu>`. Optional flags in
    // any order; the lone non-flag argument is the source path.
    //   --g / -g       toggle DWARF emission (nurl.sh forwards --debug)
    //   --no-borrowck  disable the borrow-checker analysis pass; it is
    //                  ON by default (BORROW.md Phase 8)
    //   --borrowck     accepted for compatibility — now a no-op, since
    //                  the pass is on by default
    : ~ s path ``
    : ~ i ai 1
    ~ < ai ( nurl_argc ) {
        : s a ( nurl_argv ai )
        ? | ( seq a `--g` ) ( seq a `-g` )
        { = g_dbg_enabled 1 }
        { ? ( seq a `--borrowck` )
            { = g_borrowck 1 }
            { ? ( seq a `--no-borrowck` )
                { = g_borrowck 0 }
                { = path a } } }
        = ai + ai 1
    }
    ? == 0 ( nurl_str_len path )
    { ( nurl_eprintln `usage: nurlc [--g] [--no-borrowck] <file.nu>` ) ( nurl_exit 1 ) }
    {}
    : s src ( nurl_read_file path )
    : s marker ( nurl_str_cat `@@nurl-disable` `-autodrop-strings@@` )
    ? >= ( nurl_str_find src marker ) 0
    { = g_auto_drop_strings 0 }
    {}
    : i syms ( nurl_sym_new )
    : i cg ( nurl_cg_new )
    = g_str_syms ( nurl_sym_new )
    = g_generic_syms ( nurl_sym_new )
    = g_generic_struct_syms ( nurl_sym_new )
    = g_struct_inst_syms ( nurl_sym_new )
    ( nurl_sym_def g_generic_syms `__deferred_count__` `0` )
    = g_impl_ret_syms ( nurl_sym_new )
    = g_impl_name_syms ( nurl_sym_new )
    = g_trait_syms ( nurl_sym_new )
    = g_res_type_syms ( nurl_sym_new )
    = g_closure_defs ( nurl_sym_new )
    = g_closure_types ( nurl_sym_new )
    = g_fn_inout ( nurl_sym_new )
    = g_fn_sink ( nurl_sym_new )
    = g_type_count 0
    = g_func_count 0
    = g_closure_emit_base 0
    = g_type_emit_base 0
    = g_vis_syms ( nurl_sym_new )
    ? != g_borrowck 0 { = g_bck ( nurl_sym_new ) } {}
    ( vis_set_current_src_file path )
    ( emit_header )
    ? != g_dbg_enabled 0 { ( dbg_init path ) } {}
    ( init_syms syms )
    : i lex0 ( nurl_lex_new src path )
    ( scan_generic_structs lex0 syms )
    : i lex1 ( nurl_lex_new src path )
    ( scan_fn_sigs lex1 syms )
    : i lex_tn ( nurl_lex_new src path )
    ( scan_type_names lex_tn syms )
    : i lex ( nurl_lex_new src path )
    ( parse_program lex syms cg )
    // Emit all deferred generic instantiations collected during compilation.
    ( flush_deferred_instantiations syms cg )
    ( dbg_flush )
}

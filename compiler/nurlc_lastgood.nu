// nurlc.nu — NURL compiler written in NURL.
// Grammar: v1.7
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
: i TT_EOF      0
: i TT_IDENT    1
: i TT_INT      2
: i TT_STR      3
: i TT_BOOL     4
: i TT_TYPE_KW  5
: i TT_AT       6
: i TT_COLON    7
: i TT_EQ       8
: i TT_ARROW    9
: i TT_CARET    10
: i TT_QUEST    11
: i TT_TILDE    12
: i TT_LPAREN   13
: i TT_RPAREN   14
: i TT_LBRACE   15
: i TT_RBRACE   16
: i TT_DOT      17
: i TT_HASH     18
: i TT_BANG     19
: i TT_PLUS     20
: i TT_MINUS    21
: i TT_STAR     22
: i TT_SLASH    23
: i TT_PERCENT  24
: i TT_AMP      25
: i TT_PIPE     26
: i TT_LT       27
: i TT_GT       28
: i TT_EQEQ    29
: i TT_NE       30
: i TT_LE       31
: i TT_GE       32
: i TT_LBRACK    33
: i TT_RBRACK    34
: i TT_FLOAT     35
: i TT_SIZEOF    36
: i TT_SEMICOL   37
: i TT_BACKSLASH 38
: i TT_DOLLAR    39
: i TT_QUESTQUEST 40
: i TT_SHL       41
: i TT_SHR       42

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
: i g_res_type_syms  0

// ── Type parsing ──────────────────────────────────────────────────

@ llvm_type s ty → s {
  ? ( seq ty `i` ) `i64`
  ? ( seq ty `u` ) `i8`     // unsigned 8-bit byte
  ? ( seq ty `f` ) `double`
  ? ( seq ty `b` ) `i1`
  ? ( seq ty `s` ) `i8*`
  ? ( seq ty `v` ) `void`
  ( nurl_str_cat `%` ty )
}

@ parse_type i lex → s {
  : i tt ( nurl_lex_type lex )
  ? == tt TT_STAR   { ^ ( parse_type_ptr lex ) } {}
  ? == tt TT_QUEST  { ^ ( parse_type_opt lex ) } {}
  ? == tt TT_LBRACK { ^ ( parse_type_slice lex ) } {}
  ? == tt TT_BANG   { ^ ( parse_type_res lex ) } {}
  ? == tt TT_LPAREN { ^ ( parse_type_paren lex ) } {}
  ? == tt TT_PIPE   { ^ ( parse_type_enum lex ) } {}
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
      ^ ( llvm_type v )
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
  ? ( seq lty `void` )   ^ 0
  ? ( seq lty `i64` )    ^ 8
  ? ( seq lty `double` ) ^ 8
  ? ( seq lty `i1` )     ^ 1
  ? ( seq lty `i8` )     ^ 1
  ? ( seq lty `i8*` )    ^ 8
  ? == ( nurl_str_get lty - ( nurl_str_len lty ) 1 ) 42  ^ 8  {}
  8
}

// ( @ R P* )  →  { R (i8*, P0, P1, ...)*, i8* }   closure type
// ( IDENT T+ ) →  generic_inst [Group E, currently errors]
@ parse_type_paren i lex → s {
  ( nurl_lex_advance lex )    // consume '('
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
      ( expect lex TT_RPAREN )   // consume ')'
      // Return a closure struct type: { ret (i8*, params...)*, i8* }
      : s fn_sig ( nurl_str_cat ret ` (i8*` )
      ? != 0 ( nurl_str_len params )
        { = fn_sig ( nurl_str_cat fn_sig ( nurl_str_cat `, ` params ) ) }
        {}
      = fn_sig ( nurl_str_cat fn_sig `)*` )
      ^ ( nurl_str_cat `{ ` ( nurl_str_cat fn_sig `, i8* }` ) )
    }
    { // Generic type instantiation: ( Name T1 T2 ... ) → %Name__T1__T2
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
    { ? == idx 0  ^ `i1`  {}
      ^ ( nurl_str_slice agg_ty 6 - - len 6 2 )
    }
    {}
  // Slice type: ends with ", i64 }"
  ? & >= len 7 ( seq ( nurl_str_slice agg_ty - len 7 7 ) `, i64 }` )
    { ? == idx 1  ^ `i64`  {}
      ^ ( nurl_str_slice agg_ty 2 - - len 2 7 )
    }
    {}
  `i64`
}

// ? T  →  { i1, T }
@ parse_type_opt i lex → s {
  ( nurl_lex_advance lex )
  : s inner ( parse_type lex )
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
// for compile-time try-propagation type checking.
@ parse_type_res i lex → s {
  ( nurl_lex_advance lex )
  : s lt_tok ( nurl_lex_val lex )   // capture NURL name of T before parse_type consumes it
  : s lt ( parse_type lex )
  : s le_tok ( nurl_lex_val lex )   // capture NURL name of E
  : s le ( parse_type lex )
  ( nurl_sym_def g_res_type_syms `__last_res_nurl__`     ( nurl_str_cat4 `! ` lt_tok ` ` le_tok ) )
  ( nurl_sym_def g_res_type_syms `__last_res_err_llvm__` le )
  `{ i1, i64 }`
}

// ── Emit helpers ──────────────────────────────────────────────────

@ emit s line → v { ( nurl_print line ) ( nurl_print `\n` ) }
@ emiti s line → v { ( nurl_print `  ` ) ( nurl_print line ) ( nurl_print `\n` ) }

// ── String literal encoding ───────────────────────────────────────

: i g_str_idx    0
: i g_str_syms   0  // sym handle for string-literal metadata (never pushed/popped)
: i g_did_ret    0  // set to 1 by gen_ret; checked/reset by gen_cond
: i g_defer_count 0  // number of active defers in the current function
: i g_generic_syms 0 // sym handle for stored generic function templates (Group E)
: i g_generic_struct_syms 0 // generic struct templates (Group E-structs).
                            //   <sname>__stparams → space-separated type-var names (e.g. "T" or "K V")
                            //   <sname>__sbody    → raw body source incl. outer "{ ... }"
: i g_struct_inst_syms    0 // dedupe marker — <mangled>__done → "1" once emitted
: i g_impl_ret_syms  0 // Group F: method##llvm_type → ret_type string
: i g_impl_name_syms 0 // Group F: method##llvm_type → mangle_suffix string
: i g_trait_syms     0 // Trait default implementations.
                       //   <Trait>__tparam           → trait's generic type-var name (e.g. "T")
                       //   <Trait>__defaults         → space-separated method names with defaults
                       //   <Trait>__<method>__src    → raw source "params → ret { body }"
: i g_closure_defs       0 // Deferred closure function definitions
: i g_closure_types      0 // Deferred closure type definitions
: i g_type_count         0 // Count of closure types stored
: i g_func_count         0 // Count of closure functions stored
: i g_closure_emit_base  0 // Next func index to emit (watermark)
: i g_type_emit_base     0 // Next type index to emit

// Phase 2B auto-drop-strings feature flag. Default ON. Compiler's own source
// uses patterns (strings stored via nurl_set_last_type, passed to nurl_lex_new,
// reassigned with = x literal) that Phase 2B string tracking can't handle
// safely, so nurlc.nu disables the pass for itself via a file-level pragma.
// See main() for the opt-out marker.
: i g_auto_drop_strings  1

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
  : s lty ( parse_type lex )   // parse_type already returns the LLVM type
  // Known-size base types: return string constant directly
  ? ( seq lty `void` )   { ( nurl_set_last_type `i64` ) ^ `0` } {}
  ? ( seq lty `i64` )    { ( nurl_set_last_type `i64` ) ^ `8` } {}
  ? ( seq lty `double` ) { ( nurl_set_last_type `i64` ) ^ `8` } {}
  ? ( seq lty `i1` )     { ( nurl_set_last_type `i64` ) ^ `1` } {}
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
  ( nurl_lex_advance lex )
  // Reset __last_ident_name__ so we observe what gen_expr sets below
  ( nurl_sym_def syms `__last_ident_name__` `` )
  : s val  ( gen_expr lex syms cg )
  : s lt   ( nurl_get_last_type )
  // Diagnose cases where gen_expr produced no usable value (last_type =
  // void, e.g. a `? cond then else` whose two arms have incompatible
  // types so gen_cond degrades silently to void) while the function
  // expects a real return value. Without this, gen_ret would emit
  // `ret void` from an i64-returning function and LLVM would reject it
  // downstream with the cryptic "value doesn't match function result
  // type" error.
  : s fn_rt ( nurl_sym_get syms `__fn_ret_ty__` )
  ? & & ( seq lt `void` ) != 0 ( nurl_str_len fn_rt ) ! ( seq fn_rt `void` )
    { ( die lex ( nurl_str_cat `return expression has no value (expected `
                   ( nurl_str_cat ( llvm_to_nurl fn_rt )
                     `) — likely a conditional with incompatible branch types` ) ) ) }
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
    { // defers active: store return value then branch to defer chain
      ? ! ( seq lt `void` )
        { : s rvp ( nurl_sym_get syms `__ret_val__` )
          ( nurl_print `  store ` ) ( nurl_print lt ) ( nurl_print ` ` )
          ( nurl_print val ) ( nurl_print `, ` ) ( nurl_print lt )
          ( nurl_print `* ` ) ( nurl_print rvp ) ( nurl_print `\n` )
        }
        {}
      ( nurl_print `  br label %` ) ( nurl_print dtop ) ( nurl_print `\n` )
    }
    { // no defers: drop owned slices then direct return
      ( mem_drop_owned syms cg skip )
      ? != 0 g_auto_drop_strings
        { ( mem_drop_owned_strings syms cg skip_str_ptr )
          ( mem_drop_owned_struct_fields syms cg )
          ( mem_drop_user_drops syms cg skip_user_ptr )
        }
        {}
      ? ( seq lt `void` )
        { ( emiti `ret void` ) }
        { ( nurl_print `  ret ` ) ( nurl_print lt )
          ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `\n` ) }
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
    | == tt TT_SHL == tt TT_SHR
}

@ gen_expr i lex i syms i cg → s {
  : i tt ( nurl_lex_type lex )
  ? == tt TT_INT    ( gen_int_lit lex )
  ? == tt TT_FLOAT  ( gen_float_lit lex )
  ? == tt TT_STR    ( gen_str_lit lex cg )
  ? == tt TT_BOOL   ( gen_bool_lit lex )
  ? == tt TT_SIZEOF ( gen_sizeof lex cg )
  ? == tt TT_CARET  ( gen_ret lex syms cg )
  ? == tt TT_BANG   ( gen_unary_not lex syms cg )
  ? == tt TT_QUEST  ( gen_cond lex syms cg )
  ? == tt TT_QUESTQUEST ( gen_match lex syms cg )
  ? == tt TT_LBRACE ( gen_block_expr lex syms cg )
  ? == tt TT_LPAREN ( gen_call lex syms cg )
  ? == tt TT_HASH   ( gen_cast lex syms cg )
  ? == tt TT_DOT    ( gen_member lex syms cg )
  ? == tt TT_AT        ( gen_agg_lit lex syms cg )
  ? == tt TT_BACKSLASH ( gen_backslash_expr lex syms cg )
  ? == tt TT_LBRACK    ( gen_slice_literal lex syms cg )
  ? ( is_binop_tt tt ) ( gen_binary lex syms cg )
  ? == tt TT_TILDE  ( gen_complement lex syms cg )
  ( gen_ident lex syms cg )
}

@ gen_complement i lex i syms i cg → s {
  ( nurl_lex_advance lex )
  : s v   ( gen_expr lex syms cg )
  : s lt  ( nurl_get_last_type )
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
      : s lt ( nurl_sym_get syms name )
      ( nurl_set_last_type ? == 0 ( nurl_str_len lt ) `i64` lt )
      : s ptr ( nurl_sym_get syms ( nurl_str_cat name `__ptr` ) )
      : s glb ( nurl_sym_get syms ( nurl_str_cat name `__global` ) )
      ( nurl_sym_def syms `__last_ident_name__` name )
      ^ ? != 0 ( nurl_str_len ptr )
          ( load_var cg lt ptr )
          ? != 0 ( nurl_str_len glb )
            ( load_var cg lt ( nurl_str_cat `@` name ) )
            ( nurl_str_cat `%` name )
    }
    { ( die lex `unexpected token in expression` ) }
}

// ── Binary op OP lhs rhs ─────────────────────────────────────────

@ gen_binary i lex i syms i cg → s {
  : i tt  ( nurl_lex_type lex )
  // Handle logical vs bitwise & and | operators
  ? == tt TT_AMP  ^ ( gen_logical_or_bitwise_and lex syms cg )
  ? == tt TT_PIPE ^ ( gen_logical_or_bitwise_or lex syms cg )
  // Original binary operation logic for other operators
  ( nurl_lex_advance lex )
  : s lv  ( gen_expr lex syms cg )
  : s lt  ( nurl_get_last_type )
  : s rv  ( gen_expr lex syms cg )
  : s res ( nurl_cg_reg cg )
  : b isf ( seq lt `double` )
  : b isu ( seq lt `i8` )
  : s ins ( binop_instr tt isf isu )
  ( nurl_print `  ` ) ( nurl_print res ) ( nurl_print ` = ` )
  ( nurl_print ins ) ( nurl_print ` ` )
  ( nurl_print lt ) ( nurl_print ` ` )
  ( nurl_print lv ) ( nurl_print `, ` ) ( nurl_print rv ) ( nurl_print `\n` )
  ? | & >= tt TT_LT <= tt TT_GE | == tt TT_EQEQ == tt TT_NE
    ( nurl_set_last_type `i1` )
    ( nurl_set_last_type lt )
  res
}

// ── Logical AND with short-circuit ───────────────────────────────────
@ gen_logical_and s lv s left_lbl i lex i syms i cg → s {
  : s lright ( nurl_cg_lbl cg `and_right` )
  : s lend   ( nurl_cg_lbl cg `and_end` )
  // Short-circuit: if left is false, skip right evaluation
  ( nurl_print `  br i1 ` ) ( nurl_print lv )
  ( nurl_print `, label %` ) ( nurl_print lright )
  ( nurl_print `, label %` ) ( nurl_print lend ) ( nurl_print `\n` )
  // Right branch: evaluate right operand
  ( emit ( nurl_str_cat lright `:` ) )
  ( nurl_sym_def syms `__cur_lbl__` lright )
  : s rv  ( gen_expr lex syms cg )
  : s rt  ( nurl_get_last_type )
  // Check type compatibility
  ? ! ( seq rt `i1` )
    ( die lex `operator & requires matching types — right operand must be b` )
    {}
  : s right_lbl ( nurl_sym_get syms `__cur_lbl__` )
  ( nurl_print `  br label %` ) ( nurl_print lend ) ( nurl_print `\n` )
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
  : s lend   ( nurl_cg_lbl cg `or_end` )
  // Short-circuit: if left is true, skip right evaluation
  ( nurl_print `  br i1 ` ) ( nurl_print lv )
  ( nurl_print `, label %` ) ( nurl_print lend )
  ( nurl_print `, label %` ) ( nurl_print lright ) ( nurl_print `\n` )
  // Right branch: evaluate right operand
  ( emit ( nurl_str_cat lright `:` ) )
  ( nurl_sym_def syms `__cur_lbl__` lright )
  : s rv  ( gen_expr lex syms cg )
  : s rt  ( nurl_get_last_type )
  // Check type compatibility
  ? ! ( seq rt `i1` )
    ( die lex `operator | requires matching types — right operand must be b` )
    {}
  : s right_lbl ( nurl_sym_get syms `__cur_lbl__` )
  ( nurl_print `  br label %` ) ( nurl_print lend ) ( nurl_print `\n` )
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
  : s rv  ( gen_expr lex syms cg )
  : s rt  ( nurl_get_last_type )
  // Check type compatibility
  ? ! ( seq lt rt )
    { : s op_name ? == tt TT_AMP `&` `|`
      : s msg1 ( nurl_str_cat `operator ` ( nurl_str_cat op_name ` requires matching types — got ` ) )
      : s msg2 ( nurl_str_cat ( llvm_to_nurl lt ) ( nurl_str_cat ` and ` ( llvm_to_nurl rt ) ) )
      ( die lex ( nurl_str_cat msg1 msg2 ) )
    }
    {}
  : s res ( nurl_cg_reg cg )
  : b isf ( seq lt `double` )
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
  : s lv  ( gen_expr lex syms cg )
  : s lt  ( nurl_get_last_type )
  : s left_lbl ( nurl_sym_get syms `__cur_lbl__` )
  // Determine operation type based on left operand type
  ? ( seq lt `i1` )
    { ^ ( gen_logical_and lv left_lbl lex syms cg ) }
    { ? | ( seq lt `i64` ) ( seq lt `i32` )
        { ^ ( gen_bitwise_binary lv lt lex syms cg TT_AMP ) }
        { : s msg ( nurl_str_cat `operator & requires matching types — got ` ( llvm_to_nurl lt ) )
          ( die lex ( nurl_str_cat msg ` and unknown` ) )
          ^ `error`
        }
    }
}

@ gen_logical_or_bitwise_or i lex i syms i cg → s {
  ( nurl_lex_advance lex )
  : s lv  ( gen_expr lex syms cg )
  : s lt  ( nurl_get_last_type )
  : s left_lbl ( nurl_sym_get syms `__cur_lbl__` )
  // Determine operation type based on left operand type
  ? ( seq lt `i1` )
    { ^ ( gen_logical_or lv left_lbl lex syms cg ) }
    { ? | ( seq lt `i64` ) ( seq lt `i32` )
        { ^ ( gen_bitwise_binary lv lt lex syms cg TT_PIPE ) }
        { : s msg ( nurl_str_cat `operator | requires matching types — got ` ( llvm_to_nurl lt ) )
          ( die lex ( nurl_str_cat msg ` and unknown` ) )
          ^ `error`
        }
    }
}

// `isu` = unsigned-byte (i8) operand path: selects unsigned compare
// predicates and logical (zero-fill) shift right. Equality predicates
// (`==`, `!=`) are sign-agnostic, so they take the signed entry.
@ binop_instr i tt b isf b isu → s {
  ? == tt TT_PLUS    ? isf `fadd` `add`
  ? == tt TT_MINUS   ? isf `fsub` `sub`
  ? == tt TT_STAR    ? isf `fmul` `mul`
  ? == tt TT_SLASH   ? isf `fdiv` ? isu `udiv` `sdiv`
  ? == tt TT_PERCENT ? isf `frem` ? isu `urem` `srem`
  ? == tt TT_AMP     `and`
  ? == tt TT_PIPE    `or`
  ? == tt TT_SHL     `shl`
  ? == tt TT_SHR     ? isu `lshr` `ashr`
  ? == tt TT_LT      ? isf `fcmp olt` ? isu `icmp ult` `icmp slt`
  ? == tt TT_GT      ? isf `fcmp ogt` ? isu `icmp ugt` `icmp sgt`
  ? == tt TT_EQEQ    ? isf `fcmp oeq` `icmp eq`
  ? == tt TT_NE      ? isf `fcmp one` `icmp ne`
  ? == tt TT_LE      ? isf `fcmp ole` ? isu `icmp ule` `icmp sle`
  ? == tt TT_GE      ? isf `fcmp oge` ? isu `icmp uge` `icmp sge`
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
        ? & == ch 32 == depth 0               // space at top level
          { ^ ( nurl_str_slice fn_ptr_type start_pos - space_idx start_pos ) }
          {}
        = space_idx + space_idx 1
      }
      fn_ptr_type  // fallback
    }
    { fn_ptr_type }  // Not a function pointer, return as-is
}

// Emit `call void @nurl_free(i8* %r)` for every register in `temps`
// (space-separated). Called by gen_call after a callee returns to release
// owned-string argument temporaries (Phase 2B parameter-ownership).
@ mem_drop_arg_temps s temps → v {
  : s rest temps
  ~ != 0 ( nurl_str_len rest ) {
    : s reg ( str_first_word rest )
    = rest ( str_skip_word rest )
    ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print reg ) ( nurl_print `)\n` )
  }
}

@ gen_call i lex i syms i cg → s {
  ( nurl_lex_advance lex )
  : s fname ( nurl_lex_val lex )
  ( nurl_lex_advance lex )
  // Generic instantiation: ( fname [T1 T2...] args... )
  : s call_name fname
  ? == ( nurl_lex_type lex ) TT_LBRACK
    { ( nurl_lex_advance lex )   // consume '['
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
  // Phase 2B parameter-ownership: collect register values for arg expressions
  // whose result is a fresh owned-string allocation (e.g. `nurl_str_cat`),
  // then free them right after the call returns. Without this the temp is
  // never released and leaks for the rest of the function's lifetime.
  // Convention: callees borrow i8* args and must `strdup` if they retain
  // (see runtime.c hardening for nurl_set_last_type, nurl_sym_get, ...).
  : s owned_arg_temps ``
  ~ != ( nurl_lex_type lex ) TT_RPAREN {
    ( nurl_sym_def syms `__last_call_ret_owned__` `` )
    : s av ( gen_expr lex syms cg )
    : s at ( nurl_get_last_type )
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
  }
  ( expect lex TT_RPAREN )
  // Group F: impl method dispatch based on first arg's LLVM type
  : s impl_key ( nurl_str_cat fname ( nurl_str_cat `##` first_arg_type ) )
  : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
  ? != 0 ( nurl_str_len impl_mangle_key )
    { : s impl_ret  ( nurl_sym_get g_impl_ret_syms impl_key )
      : s impl_name ( nurl_str_cat fname ( nurl_str_cat `__` impl_mangle_key ) )
      ? ( seq impl_ret `void` )
        { ( nurl_print `  call void @` ) ( nurl_print impl_name )
          ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)\n` )
          ( mem_drop_arg_temps owned_arg_temps )
          ( nurl_set_last_type `void` )
          ^ `undef`
        }
        { : s res ( nurl_cg_reg cg )
          ( nurl_print `  ` ) ( nurl_print res )
          ( nurl_print ` = call ` ) ( nurl_print impl_ret )
          ( nurl_print ` @` ) ( nurl_print impl_name )
          ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)\n` )
          ( mem_drop_arg_temps owned_arg_temps )
          ( nurl_set_last_type impl_ret )
          ^ res
        }
    }
    {}
  // Regular call
  : s rl  ( nurl_sym_get syms call_name )
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
          ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)\n` )
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
            { // Closure struct parameter
              = final_result ( call_closure_function var_llvm_val call_type argstr cg )
            }
            { // Simple function pointer parameter - call directly
              : s fn_return_type ( extract_fn_ptr_return_type rlt )
              : s res ( nurl_cg_reg cg )
              ( nurl_print `  ` ) ( nurl_print res )
              ( nurl_print ` = call ` ) ( nurl_print fn_return_type )
              ( nurl_print ` ` ) ( nurl_print var_llvm_val )
              ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)\n` )
              ( nurl_set_last_type fn_return_type )
              = final_result res
            }
          ( mem_drop_arg_temps owned_arg_temps )
          final_result
        }
        {
      // Regular function call
      ? ( seq rlt `void` )
        { ( nurl_print `  call void @` ) ( nurl_print call_name )
          ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)\n` )
          ( mem_drop_arg_temps owned_arg_temps )
          ( nurl_set_last_type `void` )
          `undef`
        }
        { : s res ( nurl_cg_reg cg )
          ( nurl_print `  ` ) ( nurl_print res )
          ( nurl_print ` = call ` ) ( nurl_print rlt )
          ( nurl_print ` @` ) ( nurl_print call_name )
          ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)\n` )
          ( mem_drop_arg_temps owned_arg_temps )
          ( nurl_set_last_type rlt )
          res
        }
        }
    }
}

// ── Conditional ? cond then else ──────────────────────────────────

@ gen_cond i lex i syms i cg → s {
  ( nurl_lex_advance lex )
  : s cv   ( gen_expr lex syms cg )
  : s ct   ( nurl_get_last_type )
  // Allow non-i1 integer conditions (e.g. `? & i64a i64b { … }`) by
  // narrowing to i1 via `icmp ne … 0`.
  = cv ( coerce_to_i1 cv ct cg )
  : s lt   ( nurl_cg_lbl cg `then` )
  : s le   ( nurl_cg_lbl cg `else` )
  : s lend ( nurl_cg_lbl cg `end` )
  ( nurl_print `  br i1 ` ) ( nurl_print cv )
  ( nurl_print `, label %` ) ( nurl_print lt )
  ( nurl_print `, label %` ) ( nurl_print le ) ( nurl_print `\n` )
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
    { = old_strs_t    ( nurl_sym_get syms `__owned_strings__` )
      = old_structs_t ( nurl_sym_get syms `__owned_struct_fields__` )
      = old_user_t    ( nurl_sym_get syms `__user_drops__` )
      ( nurl_sym_push syms )
    } {}
  ( nurl_sym_def syms `__cur_lbl__` lt )
  = g_did_ret 0
  : s tv  ( gen_expr lex syms cg )
  : s tt2 ( nurl_get_last_type )
  : s tlbl ( nurl_sym_get syms `__cur_lbl__` )
  : i tdr g_did_ret
  ? == tdr 0
    { // Phase 2D: arm-local fall-through drop. Only safe when the arm's
      // result type is void — otherwise tv may reference memory backed by
      // one of the arm-local allocas we're about to free (UAF in the phi
      // consumer at %lend). Arm-result ownership transfer would require
      // Phase 2A-style tracking; out of scope here.
      ? & != 0 g_auto_drop_strings ( seq tt2 `void` )
        { ( mem_drop_new_strings syms cg old_strs_t )
          ( mem_drop_new_struct_fields syms cg old_structs_t )
          ( mem_drop_new_user_drops syms cg old_user_t ) } {}
      ( nurl_print `  br label %` ) ( nurl_print lend ) ( nurl_print `\n` )
    } {}
  ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}
  ( emit ( nurl_str_cat le `:` ) )
  : s old_strs_e ``
  : s old_structs_e ``
  : s old_user_e ``
  ? != 0 g_auto_drop_strings
    { = old_strs_e    ( nurl_sym_get syms `__owned_strings__` )
      = old_structs_e ( nurl_sym_get syms `__owned_struct_fields__` )
      = old_user_e    ( nurl_sym_get syms `__user_drops__` )
      ( nurl_sym_push syms )
    } {}
  ( nurl_sym_def syms `__cur_lbl__` le )
  = g_did_ret 0
  : s ev  ( gen_expr lex syms cg )
  : s et2 ( nurl_get_last_type )
  : s elbl ( nurl_sym_get syms `__cur_lbl__` )
  : i edr g_did_ret
  ? == edr 0
    { ? & != 0 g_auto_drop_strings ( seq et2 `void` )
        { ( mem_drop_new_strings syms cg old_strs_e )
          ( mem_drop_new_struct_fields syms cg old_structs_e )
          ( mem_drop_new_user_drops syms cg old_user_e ) } {}
      ( nurl_print `  br label %` ) ( nurl_print lend ) ( nurl_print `\n` )
    } {}
  ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}
  ( emit ( nurl_str_cat lend `:` ) )
  ( nurl_sym_def syms `__cur_lbl__` lend )
  // The whole conditional only "did_ret" if BOTH branches did. If either
  // branch falls through, %lend is reachable and the parent must keep
  // emitting code (and a `br parent_end` from this position). Without
  // this reset, deeply chained `? a {} { ? b {} { ? c {} { ^ … } } }`
  // patterns leave g_did_ret=1 on the way out and the parent skips its
  // `br`, producing label cascades with no terminators (LLVM error
  // "expected instruction opcode").
  ? & != 0 tdr != 0 edr { ( emiti `unreachable` ) = g_did_ret 1 } { = g_did_ret 0 }
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
    ( nurl_print `, label %` ) ( nurl_print fail_label ) ( nurl_print `\n` )
    ( nurl_print ok_label ) ( nurl_print `:\n` )
  }
}

@ gen_match i lex i syms i cg → s {
  ( nurl_lex_advance lex )  // consume '??'

  // Peek the variable name (if any) BEFORE gen_expr consumes it, so we
  // can later look up `<name>__res_nurl_T` (set by gen_let_or_struct)
  // to know the source-level NURL T of an `! T E` value being matched.
  : s match_var_name ? ( is_ident_tok ( nurl_lex_type lex ) ) ( nurl_lex_val lex ) ``

  // Generate the value to match against
  : s match_val ( gen_expr lex syms cg )
  : s match_type ( nurl_get_last_type )

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
  : ~ s phi_type    ``
  : ~ b phi_ok      T
  : ~ i phi_count   0
  // arms_total / arms_ret count every parsed arm vs. those that ended
  // in `^`. When equal AND a fallback_pred is set, the `match_end`
  // label is reached only through the synthetic last-arm fallthrough
  // br — there is no real value flow, no phi entries, and the function
  // continues with no further code. Emit `unreachable` at end_label so
  // the function block is well-formed.
  : ~ i arms_total  0
  : ~ i arms_ret    0
  // fallback_pred = label of the open block right before the trailing
  // `br end_label` after the loop.  Empty when that br lands inside an
  // already-terminated block (wildcard-last) and is therefore dead.
  : ~ s fallback_pred ``

  // Exhaustive match tracking
  : s seen_variants ``
  : i has_wildcard 0

  // Process all match arms
  ~ != ( nurl_lex_type lex ) TT_RBRACE {
    : i pat_tt ( nurl_lex_type lex )
    ? | ( is_ident_tok pat_tt ) == pat_tt TT_BOOL {
      // Parse pattern name (IDENT, TYPE_KW, or BOOL for T/F option patterns)
      : s pattern_name ( nurl_lex_val lex )
      ( nurl_lex_advance lex )

      // Collect up to 3 payload slots before the arrow.  Each slot is either
      // an identifier (binds the payload) or an integer literal (compared).
      : s pv0 ``
      : s pv1 ``
      : s pv2 ``
      : s lit0 ``
      : s lit1 ``
      : s lit2 ``
      : i pvc 0
      ~ != ( nurl_lex_type lex ) TT_ARROW {
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
        ( nurl_print `  br label %` ) ( nurl_print arm_label ) ( nurl_print `\n` )
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
        // If match_val is already a bare i1 (e.g. `?? some_bool_var`), use it as
        // the tag directly — no extractvalue needed (i1 is not an aggregate).
        : b match_is_i1 ( seq match_type `i1` )
        : s tag_reg ? match_is_i1 match_val ( nurl_cg_reg cg )
        ? match_is_i1 {} {
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
        ( nurl_print `, label %` ) ( nurl_print next_label ) ( nurl_print `\n` )
        // Emit chained literal comparisons.  Each failure jumps to next_label;
        // the last successful check falls through to arm_label.
        ? has_lit {
          ( nurl_print tag_ok_label ) ( nurl_print `:\n` )
          ( emit_lit_check cg syms match_val match_type pattern_name 0 lit0 next_label )
          ( emit_lit_check cg syms match_val match_type pattern_name 1 lit1 next_label )
          ( emit_lit_check cg syms match_val match_type pattern_name 2 lit2 next_label )
          ( nurl_print `  br label %` ) ( nurl_print arm_label ) ( nurl_print `\n` )
        } {}
      }

      // Generate the arm code
      ( nurl_print arm_label ) ( nurl_print `:\n` )
      ( nurl_sym_def syms `__cur_lbl__` arm_label )
      // Scope each match arm so payload bindings and owned-string entries
      // don't leak into sibling arms (see gen_cond for the same reasoning).
      : s old_strs_m ``
      : s old_structs_m ``
      ? != 0 g_auto_drop_strings
        { = old_strs_m    ( nurl_sym_get syms `__owned_strings__` )
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
              { : s nurl_inner_llvm ( nurl_sym_get syms nurl_inner_t )
                ? & != 0 ( nurl_str_len nurl_inner_llvm )
                     == ( nurl_str_get nurl_inner_llvm 0 ) 37
                  { : s sname_r ( nurl_str_slice nurl_inner_llvm 1 - ( nurl_str_len nurl_inner_llvm ) 1 )
                    : s vlist_r ( nurl_sym_get syms ( nurl_str_cat sname_r `__variants` ) )
                    ? == 0 ( nurl_str_len vlist_r )
                      { // Struct payload reconstruction. Two shapes:
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
                            { // Heap-box multi-field struct: load + free.
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
                              ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print ubraw_s ) ( nurl_print `)\n` )
                              = pt0_eff nurl_inner_llvm
                              = pr0_eff ubv_s
                              = did_reconstruct T }
                            {} }
                      { // Wide enum unbox: i64 → %T*  → load %T → free.
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
                          ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print ubraw ) ( nurl_print `)\n` )
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
              ? == ( nurl_str_get pt0 0 ) 123
                { // Anonymous aggregate (e.g., { i1, i64 }): load value from ptr
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
            { // Anonymous aggregate: load value from ptr
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
            { // Anonymous aggregate: load value from ptr
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
      : s arm_result ( gen_stmt lex syms cg )
      : s arm_type   ( nurl_get_last_type )
      : s arm_lbl    ( nurl_sym_get syms `__cur_lbl__` )
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
        ( nurl_print `  br label %` ) ( nurl_print end_label ) ( nurl_print `\n` )
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
    { ( nurl_print `  br label %` ) ( nurl_print end_label ) ( nurl_print `\n` ) }
    {}

  // End label
  ( nurl_print end_label ) ( nurl_print `:\n` )
  ( nurl_sym_def syms `__cur_lbl__` end_label )

  // All arms ended in `^` AND the trailing fallback br landed here:
  // end_label is technically reachable but the match is exhaustive,
  // so no real path arrives. Emit unreachable + flag did_ret so the
  // function epilogue doesn't try to ret void into a non-void return.
  ? & & > arms_total 0 == arms_ret arms_total != 0 ( nurl_str_len fallback_pred )
    { ( emiti `unreachable` ) = g_did_ret 1 } { = g_did_ret 0 }

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
  : s slice_val ( gen_expr lex syms cg )
  : s slice_ty  ( nurl_get_last_type )
  // slice_ty = "{ T*, i64 }" — extract ptr_ty (T*) then elem_ty (T)
  : i slen     ( nurl_str_len slice_ty )
  : s ptr_ty   ( nurl_str_slice slice_ty 2 - - slen 7 2 )
  : s elem_ty  ( nurl_str_slice ptr_ty 0 - ( nurl_str_len ptr_ty ) 1 )
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
  ( nurl_print `  br label %` ) ( nurl_print lc ) ( nurl_print `\n` )
  // Check: idx < len
  ( emit ( nurl_str_cat lc `:` ) )
  ( nurl_sym_def syms `__cur_lbl__` lc )
  : s idx_cur ( nurl_cg_reg cg )
  ( nurl_print `  ` ) ( nurl_print idx_cur )
  ( nurl_print ` = load i64, i64* ` ) ( nurl_print idx_ptr ) ( nurl_print `\n` )
  : s cond ( nurl_cg_reg cg )
  ( nurl_print `  ` ) ( nurl_print cond )
  ( nurl_print ` = icmp slt i64 ` ) ( nurl_print idx_cur )
  ( nurl_print `, ` ) ( nurl_print len_val ) ( nurl_print `\n` )
  ( nurl_print `  br i1 ` ) ( nurl_print cond )
  ( nurl_print `, label %` ) ( nurl_print lb )
  ( nurl_print `, label %` ) ( nurl_print le ) ( nurl_print `\n` )
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
    { = old_strs_fe    ( nurl_sym_get syms `__owned_strings__` )
      = old_structs_fe ( nurl_sym_get syms `__owned_struct_fields__` )
      = old_user_fe    ( nurl_sym_get syms `__user_drops__` )
      ( nurl_sym_push syms )
    } {}
  = g_did_ret 0
  ( gen_block_stmts lex syms cg )
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
      ( nurl_print `  br label %` ) ( nurl_print lc ) ( nurl_print `\n` )
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
  : i start_pos ( nurl_lex_cur_start lex )
  ( nurl_lex_advance lex )
  // For-each: ~ IDENT(var) IDENT(slice) { body }
  ? & == ( nurl_lex_type lex ) TT_IDENT == ( nurl_lex_peek_type lex ) TT_IDENT
    { ^ ( gen_foreach lex syms cg ) }
    {}
  
  // While loop: ~ cond { body }
  // We need to see if a block follows. If not, this was a complement expression.
  : s lc ( nurl_cg_lbl cg `loop_check` )
  : s lb ( nurl_cg_lbl cg `loop_body` )
  : s le ( nurl_cg_lbl cg `loop_exit` )
  
  // Speculatively parse condition
  : s cv ( gen_expr lex syms cg )
  ? == ( nurl_lex_type lex ) TT_LBRACE
    {
      // It's a loop! Emit the control flow.
      // We already emitted some expression IR into the current block, but we need it in lc.
      // Easiest is to re-parse it in the right place.
      ( nurl_lex_set_pos lex start_pos )
      ( nurl_lex_advance lex )
      
      ( nurl_print `  br label %` ) ( nurl_print lc ) ( nurl_print `\n` )
      ( emit ( nurl_str_cat lc `:` ) )
      ( nurl_sym_def syms `__cur_lbl__` lc )
      = cv ( gen_expr lex syms cg )
      // Narrow non-i1 integer loop conditions (see gen_cond).
      = cv ( coerce_to_i1 cv ( nurl_get_last_type ) cg )
      ( nurl_print `  br i1 ` ) ( nurl_print cv )
      ( nurl_print `, label %` ) ( nurl_print lb )
      ( nurl_print `, label %` ) ( nurl_print le ) ( nurl_print `\n` )
      ( emit ( nurl_str_cat lb `:` ) )
      // Scope the loop body so `:` bindings don't leak into the outer
      // `__owned_strings__` list (see gen_cond for the same reasoning).
      : s old_strs_lp ``
      : s old_structs_lp ``
      ? != 0 g_auto_drop_strings
        { = old_strs_lp    ( nurl_sym_get syms `__owned_strings__` )
          = old_structs_lp ( nurl_sym_get syms `__owned_struct_fields__` )
          ( nurl_sym_push syms )
        } {}
      ( nurl_sym_def syms `__cur_lbl__` lb )
      = g_did_ret 0
      ( gen_block_stmts lex syms cg )
      ? == g_did_ret 0
        { ? != 0 g_auto_drop_strings
            { ( mem_drop_new_strings syms cg old_strs_lp )
              ( mem_drop_new_struct_fields syms cg old_structs_lp ) } {}
          ( nurl_print `  br label %` ) ( nurl_print lc ) ( nurl_print `\n` )
        } {}
      ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}
      ( emit ( nurl_str_cat le `:` ) )
      ( nurl_sym_def syms `__cur_lbl__` le )
      ( nurl_set_last_type `void` )
      ^ `undef`
    }
    {
      // No block follows, must be a complement expression.
      // Backtrack and let gen_expr handle it.
      ( nurl_lex_set_pos lex start_pos )
      ^ ( gen_expr lex syms cg )
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
  ( nurl_print `  br label %` ) ( nurl_print lafter ) ( nurl_print `\n` )
  // Emit the defer block
  ( emit ( nurl_str_cat ldefer `:` ) )
  ( nurl_sym_def syms `__cur_lbl__` ldefer )
  = g_did_ret 0
  ( gen_block_stmts lex syms cg )
  // After the defer block: chain to previous defer or to fn_cleanup
  ? == g_did_ret 0
    { ? != 0 ( nurl_str_len prev_top )
        { ( nurl_print `  br label %` ) ( nurl_print prev_top ) ( nurl_print `\n` ) }
        { : s fc ( nurl_sym_get syms `__fn_cleanup__` )
          ( nurl_print `  br label %` ) ( nurl_print fc ) ( nurl_print `\n` )
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
  ( nurl_lex_advance lex )
  : s last `undef`
  ~ != ( nurl_lex_type lex ) TT_RBRACE {
    = last ( gen_stmt lex syms cg )
  }
  ( nurl_lex_advance lex )
  last
}

@ gen_block_stmts i lex i syms i cg → v {
  ( expect lex TT_LBRACE )
  ~ != ( nurl_lex_type lex ) TT_RBRACE {
    ( gen_stmt lex syms cg )
  }
  ( expect lex TT_RBRACE )
}

// gen_block_ret: like gen_block_stmts but returns the last stmt value.
@ gen_block_ret i lex i syms i cg → s {
  ( expect lex TT_LBRACE )
  : s last `undef`
  ~ != ( nurl_lex_type lex ) TT_RBRACE {
    = last ( gen_stmt lex syms cg )
  }
  ( expect lex TT_RBRACE )
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
            ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print raw ) ( nurl_print `)\n` )
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
            ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print v ) ( nurl_print `)\n` )
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
        : s leaf_idx   ( nurl_str_slice after2 + c3 1 - - ( nurl_str_len after2 ) c3 1 )
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
      ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print fv ) ( nurl_print `)\n` )
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
      ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print raw ) ( nurl_print `)\n` )
    }
}

@ mem_drop_owned_struct_fields i syms i cg → v {
  : s dtop ( nurl_sym_get syms `__defer_top__` )
  ? == 0 ( nurl_str_len dtop )
    { : s rest ( nurl_sym_get syms `__owned_struct_fields__` )
      ~ != 0 ( nurl_str_len rest ) {
        : s ptr        ( str_first_word rest ) = rest ( str_skip_word rest )
        : s sname      ( str_first_word rest ) = rest ( str_skip_word rest )
        : s path       ( str_first_word rest ) = rest ( str_skip_word rest )
        : s kind       ( str_first_word rest ) = rest ( str_skip_word rest )
        : s leaf_sname ( str_first_word rest ) = rest ( str_skip_word rest )
        : s leaf_idx   ( str_first_word rest ) = rest ( str_skip_word rest )
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
            ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print v ) ( nurl_print `)\n` )
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
            : s ptr        ( str_first_word rest ) = rest ( str_skip_word rest )
            : s sname      ( str_first_word rest ) = rest ( str_skip_word rest )
            : s path       ( str_first_word rest ) = rest ( str_skip_word rest )
            : s kind       ( str_first_word rest ) = rest ( str_skip_word rest )
            : s leaf_sname ( str_first_word rest ) = rest ( str_skip_word rest )
            : s leaf_idx   ( str_first_word rest ) = rest ( str_skip_word rest )
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
        : s vt  ( str_first_word rest ) = rest ( str_skip_word rest )
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
                ( nurl_print `(` ) ( nurl_print vt ) ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `)\n` )
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
            : s vt  ( str_first_word rest ) = rest ( str_skip_word rest )
            : s impl_key ( nurl_str_cat `drop##` vt )
            : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
            ? != 0 ( nurl_str_len impl_mangle_key )
              { : s impl_name ( nurl_str_cat `drop__` impl_mangle_key )
                : s v ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print v )
                ( nurl_print ` = load ` ) ( nurl_print vt ) ( nurl_print `, ` ) ( nurl_print vt )
                ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                ( nurl_print `  call void @` ) ( nurl_print impl_name )
                ( nurl_print `(` ) ( nurl_print vt ) ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `)\n` )
              }
              {}
          }
        }
        {}
    }
    {}
}

// ── Statement ──────────────────────────────────────────────────────

@ gen_stmt i lex i syms i cg → s {
  : i tt ( nurl_lex_type lex )
  ? == tt TT_COLON   ( gen_let_or_struct lex syms cg )
  ? == tt TT_EQ      ( gen_assign lex syms cg )
  ? == tt TT_TILDE   ( gen_loop lex syms cg )
  ? == tt TT_SEMICOL ( gen_defer lex syms cg )
  ( gen_expr lex syms cg )
}

@ gen_let_or_struct i lex i syms i cg → s {
  ( nurl_lex_advance lex )
  // Check for optional ~ (mutable) token
  : b had_mutability_check | == ( nurl_lex_type lex ) TT_TILDE ( is_type_start ( nurl_lex_type lex ) )
  : b is_mutable == ( nurl_lex_type lex ) TT_TILDE
  ? is_mutable { ( nurl_lex_advance lex ) } {}
  // Check if first token could be a type name by looking it up in symbol table
  ? & == ( nurl_lex_type lex ) TT_IDENT == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_lex_val lex ) ) )
    { // Type inference: plain IDENT that's not a known type
      : s name ( nurl_lex_val lex )
      ( nurl_lex_advance lex )
      : b rhs_is_slice_lit == ( nurl_lex_type lex ) TT_LBRACK
      ( nurl_sym_def syms `__last_call_ret_owned__` `` )
      ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
      : s val ( gen_expr lex syms cg )
      : s vt  ( nurl_get_last_type )
      : b rhs_is_owned_call != 0 ( nurl_str_len ( nurl_sym_get syms `__last_call_ret_owned__` ) )
      : s ptr ( nurl_cg_reg cg )
      ( nurl_print `  ` ) ( nurl_print ptr )
      ( nurl_print ` = alloca ` ) ( nurl_print vt ) ( nurl_print `\n` )
      ( nurl_print `  store ` ) ( nurl_print vt ) ( nurl_print ` ` )
      ( nurl_print val ) ( nurl_print `, ` ) ( nurl_print vt )
      ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
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
      : s ptype ( parse_type lex )
      // Capture the NURL form of `! T E` when present, so gen_match can
      // recover the inner T (e.g. `Json`) for struct-handle reconstruction.
      // parse_type's recursive descent through parse_type_res leaves the
      // outermost `! T E` form here; nested ones get overwritten but only
      // the outer one matters at this binding.
      : s let_res_nurl ( nurl_sym_get g_res_type_syms `__last_res_nurl__` )
      ? ( is_ident_tok ( nurl_lex_type lex ) )
        { : s name ( nurl_lex_val lex )
          ( nurl_lex_advance lex )
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
          ? == ( nurl_lex_type lex ) TT_LBRACE
            { ( nurl_lex_advance lex )
              ~ != ( nurl_lex_type lex ) TT_RBRACE { ( nurl_lex_advance lex ) }
              ( nurl_lex_advance lex )
              ^ `undef`
            }
            { : b rhs_is_slice_lit == ( nurl_lex_type lex ) TT_LBRACK
              ( nurl_sym_def syms `__last_call_ret_owned__` `` )
              ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
              : s val ( gen_expr lex syms cg )
              : s vt  ( nurl_get_last_type )
              : b rhs_is_owned_call != 0 ( nurl_str_len ( nurl_sym_get syms `__last_call_ret_owned__` ) )

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
      : s vt  ( nurl_sym_get syms name )
      : s ptr ( nurl_sym_get syms ( nurl_str_cat name `__ptr` ) )
      : s glb ( nurl_sym_get syms ( nurl_str_cat name `__global` ) )
      : s param_check ( nurl_sym_get syms ( nurl_str_cat name `__param` ) )
      // Check mutability only for variables using new syntax
      : s newsyntax_check ( nurl_sym_get syms ( nurl_str_cat name `__newsyntax` ) )
      ? != 0 ( nurl_str_len newsyntax_check )
        { // Variable uses new syntax, check if it's mutable
          ? == 0 ( nurl_str_len mut_check )
            { // Variable exists with new syntax but is immutable
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
      : s val ( gen_expr lex syms cg )
      : b rhs_is_owned_call & lhs_is_owned_str
                              ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` )
      ? rhs_is_owned_call
        { : s old_reg ( nurl_cg_reg cg )
          ( nurl_print `  ` ) ( nurl_print old_reg )
          ( nurl_print ` = load i8*, i8** ` ) ( nurl_print ptr ) ( nurl_print `\n` )
          ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print old_reg ) ( nurl_print `)\n` )
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
      ^ store_val
    }
    { ( die lex `expected name after =` ) }
}

// ── Field store = . ptr field val ─────────────────────────────────────
// Emits GEP + store for = . ptr_expr field_name rhs_expr.
// Called after gen_assign has already consumed '='.
// Precondition: current token is TT_DOT.

@ gen_field_store i lex i syms i cg → s {
  ( nurl_lex_advance lex )             // consume '.'
  // Save object name before gen_expr consumes the token (needed for struct-by-value alloca lookup)
  : s obj_name ? ( is_ident_tok ( nurl_lex_type lex ) ) ( nurl_lex_val lex ) ``
  : s pv ( gen_expr lex syms cg )     // pointer/aggregate value
  : s pt ( nurl_get_last_type )       // LLVM type, e.g. "%Node*", "i64*", "{ T*, i64 }", or "%Pair"

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
        { // Numeric index: array access like raw_ptr[0] = value
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
        { // Not TT_INT: struct field name or raw-pointer variable index
          : i ptlen ( nurl_str_len pt )
          : b pt_is_ptr == ( nurl_str_get pt - ptlen 1 ) 42
          ? pt_is_ptr
            { // pt ends with '*': pointer to struct OR raw pointer
              : s st ( nurl_str_slice pt 0 - ptlen 1 )
              ? == ( nurl_str_get st 0 ) 37
                { // Struct pointer "%T*": next token is either a field
                  // name or a variable used as array index (e.g. data[i]
                  // where data: *Struct). Prioritize field name if it exists.
                  : i stlen ( nurl_str_len st )
                  : s sname ( nurl_str_slice st 1 - stlen 1 )
                  : s fname ( nurl_lex_val lex )
                  : s var_t ( nurl_sym_get syms fname )
                  ? > ( int_width var_t ) 0
                    { // IDENT is an integer variable: array-style store *T[idx] = rhs
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
                    { // Not an integer variable: check if it is a field name
                      : s fidx_s ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
                      ? != 0 ( nurl_str_len fidx_s )
                        { // IDENT is a field name: struct field access
                          ( nurl_lex_advance lex )
                          : s ftype  ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
                          : i fidx   ( nurl_str_to_int fidx_s )
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
                        { // Neither integer variable nor field: check for non-integer variable index (error likely but follow general path)
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
                { // Raw pointer with variable index: one-index GEP
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
            { // Struct by value "%T": use alloca ptr from obj_name__ptr as GEP base
              : s alloca_ptr ( nurl_sym_get syms ( nurl_str_cat obj_name `__ptr` ) )
              : s pt_ptr ( nurl_str_cat pt `*` )
              : s sname ( nurl_str_slice pt 1 - ptlen 1 )
              : s fname ( nurl_lex_val lex )
              ( nurl_lex_advance lex )
              : s fidx_s ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
              : s ftype  ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
              : i fidx   ( nurl_str_to_int fidx_s )
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
  ? ( seq ty `i1` )   1
  ? ( seq ty `i8` )   8
  ? ( seq ty `i16` )  16
  ? ( seq ty `i32` )  32
  ? ( seq ty `i64` )  64
  0
}

@ gen_cast i lex i syms i cg → s {
  ( nurl_lex_advance lex )
  : s dt  ( parse_type lex )
  : s val ( gen_expr lex syms cg )
  : s st  ( nurl_get_last_type )
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
      ( nurl_lex_advance lex )                        // consume the 0 / 1
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
  ? & ( seq st `double` ) ! ( seq dt `double` )
    { ( nurl_print `  ` ) ( nurl_print res )
      ( nurl_print ` = fptosi double ` ) ( nurl_print val )
      ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
      ( nurl_set_last_type dt )
      ^ res
    }
    ? & ! ( seq st `double` ) ( seq dt `double` )
      { ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ` = sitofp ` ) ( nurl_print st )
        ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print ` to double\n` )
        ( nurl_set_last_type `double` )
        ^ res
      }
      { ? & src_ptr ( seq dt `i64` )
          { // pointer → i64: ptrtoint
            ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = ptrtoint ` ) ( nurl_print st )
            ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print ` to i64\n` )
            ( nurl_set_last_type `i64` )
            ^ res
          }
          { ? & dst_ptr ( seq st `i64` )
              { // i64 → pointer: inttoptr
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = inttoptr i64 ` ) ( nurl_print val )
                ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
                ( nurl_set_last_type dt )
                ^ res
              }
              { ? & src_ptr dst_ptr
                  { // pointer → pointer: bitcast
                    ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = bitcast ` ) ( nurl_print st )
                    ( nurl_print ` ` ) ( nurl_print val )
                    ( nurl_print ` to ` ) ( nurl_print dt ) ( nurl_print `\n` )
                    ( nurl_set_last_type dt )
                    ^ res
                  }
                  { ? & ( seq st `i64` ) == ( nurl_str_get dt 0 ) 37
                      { // i64 → struct/enum: reconstruct by inserting val
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
                              { // f0 is neither pointer, i64, nor unknown —
                                // produce a zero-initialised whole struct.
                                ( nurl_set_last_type dt )
                                ^ `zeroinitializer` }
                          }
                      }
                      { // Integer-width conversion (iN → iM).  zext if dst is
                        // wider, trunc if narrower.  Falls through to no-op
                        // when widths are equal or the types aren't integers.
                        : i sw ( int_width st )
                        : i dw ( int_width dt )
                        ? & & > sw 0 > dw 0 != sw dw
                          { ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ? > dw sw ` = zext ` ` = trunc ` )
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

  // Check object type first to determine access method
  : i otlen ( nurl_str_len ot )
  : b is_ptr == ( nurl_str_get ot - otlen 1 ) 42

  ? is_ptr
    { // Pointer type. Disambiguate raw pointer (T*) vs struct pointer (%T*):
      //   - INT literal     →  array indexing (works for both)
      //   - IDENT field name on a STRUCT pointer  →  GEP + load by registered field idx
      //   - IDENT variable  →  variable-index array access (raw pointers only)
      ? == ( nurl_lex_type lex ) TT_INT
        { // Integer literal index
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
                {} // Integer variable index: skip field access check
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
            { ( nurl_lex_advance lex )                  // consume field name
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
            { // Variable / arbitrary expression index → array-style access
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
              ^ res
            }
        }
    }
    { // Non-pointer type: handle struct field access or aggregate indexing
      ? == ( nurl_lex_type lex ) TT_INT
        { // Integer literal index for aggregate types
          : i idx ( nurl_lex_inum lex )
          ( nurl_lex_advance lex )
          : b ot_is_opt_res & >= ( nurl_str_len ot ) 6
                               ( seq ( nurl_str_slice ot 0 6 ) `{ i1, ` )
          ? & | == ( nurl_str_get ot 0 ) 37 ot_is_opt_res
                == idx 0
            { // Named struct/enum (%T) or opt/res aggregate ({ i1, T }) at index 0:
              // Return the whole value — consumed by `??` which extractvalues the tag itself.
              // Slices `{ T*, i64 }` are NOT matched here: `. slice 0` must extract
              // the data pointer via the `else` branch below.
              ( nurl_set_last_type ot )
              ^ ov
            }
            { // Extractvalue for specific field (idx > 0) or primitive types
              : s ft  ( compound_field_type ot idx )
              : s res ( nurl_cg_reg cg )
              ( nurl_print `  ` ) ( nurl_print res )
              ( nurl_print ` = extractvalue ` ) ( nurl_print ot )
              ( nurl_print ` ` ) ( nurl_print ov )
              ( nurl_print `, ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
              ( nurl_set_last_type ft )
              ^ res
            }
        }
        { // Named field access for structs or slice types
          ? ( is_ident_tok ( nurl_lex_type lex ) )
            { : s fname ( nurl_lex_val lex )
              ( nurl_lex_advance lex )
              // Slice type check: compound type starts with '{' (ASCII 123)
              // Slice layout: { T*, i64 }  — ptr at index 0, length at index 1
              ? == ( nurl_str_get ot 0 ) 123
                { // Slice: "ptr" → extractvalue 0, "length" → extractvalue 1,
                  //         anything else → variable element index
                  ? ( seq fname `ptr` )
                    { // ptr: extractvalue 0, type = T*
                      : s ptr_ty ( nurl_str_slice ot 2 - - ( nurl_str_len ot ) 7 2 )
                      : s res ( nurl_cg_reg cg )
                      ( nurl_print `  ` ) ( nurl_print res )
                      ( nurl_print ` = extractvalue ` ) ( nurl_print ot )
                      ( nurl_print ` ` ) ( nurl_print ov ) ( nurl_print `, 0\n` )
                      ( nurl_set_last_type ptr_ty )
                      ^ res
                    }
                    { ? ( seq fname `length` )
                        { // length: extractvalue 1, type = i64
                          : s res ( nurl_cg_reg cg )
                          ( nurl_print `  ` ) ( nurl_print res )
                          ( nurl_print ` = extractvalue ` ) ( nurl_print ot )
                          ( nurl_print ` ` ) ( nurl_print ov ) ( nurl_print `, 1\n` )
                          ( nurl_set_last_type `i64` )
                          ^ res
                        }
                        { // Variable element index: extract data ptr, GEP, load
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
                { // Regular struct: use symtable lookup
                  // Strip '%' to get struct name  e.g. "%Node" → "Node"
                  : s sname ( nurl_str_slice ot 1 - otlen 1 )
                  : s fidx_s ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
                  : s ftype  ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
                  : i fidx   ( nurl_str_to_int fidx_s )
                  : s res    ( nurl_cg_reg cg )
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
  ( nurl_lex_advance lex )       // consume '@'
  : s agg_ty ( parse_type lex )  // parse the aggregate type
  ( expect lex TT_LBRACE )       // consume '{'
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
  ~ != ( nurl_lex_type lex ) TT_RBRACE {
    ? != 0 g_auto_drop_strings
      { ( nurl_sym_def syms `__last_call_ret_owned__` `` )
        ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
      }
      {}
    // Snapshot whether this field expr is a slice literal before gen_expr
    // consumes the token. Slice literals don't go through gen_call so
    // `__last_call_ret_owned__` is never set for them.
    : b fld_is_slice_lit == ( nurl_lex_type lex ) TT_LBRACK
    : s fval ( gen_expr lex syms cg )
    : s fty  ( nurl_get_last_type )
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
      { // Detect opt/res aggregate: starts with "{ i1, " (6 chars).
        // For opt types the payload field type = T (may be struct %Foo or i64 or i8*).
        // For res types the payload field type is always i64.
        // Only coerce when the expected payload type ≠ value type.
        : b is_opt_res & >= ( nurl_str_len agg_ty ) 6
                          ( seq ( nurl_str_slice agg_ty 0 6 ) `{ i1, ` )
        : s payload_ty ? is_opt_res ( compound_field_type agg_ty 1 ) ``
        : b payload_matches & is_opt_res ( seq payload_ty fty )
        ? is_opt_res
          { // opt/res payload. If value type already matches the payload field
            // type (e.g. `? Node` payload is %Node, value is %Node), no coercion.
            // Otherwise coerce to the payload type — for `! T E` the payload slot
            // is always i64, so string/bool/enum values are folded to i64.
            ? payload_matches
              {} // value already matches payload_ty: use as-is
              { ? | ( seq fty `i8*` ) ( seq fty `sref` )
                  { // string → i64 via ptrtoint
                    : s conv_reg ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print conv_reg )
                    ( nurl_print ` = ptrtoint ` ) ( nurl_print fty ) ( nurl_print ` ` )
                    ( nurl_print fval ) ( nurl_print ` to i64\n` )
                    = actual_fval conv_reg
                    = actual_fty `i64`
                  }
                  ? ( seq fty `i1` )
                    { // bool → i64 via zext
                      : s conv_reg ( nurl_cg_reg cg )
                      ( nurl_print `  ` ) ( nurl_print conv_reg )
                      ( nurl_print ` = zext i1 ` ) ( nurl_print fval ) ( nurl_print ` to i64\n` )
                      = actual_fval conv_reg
                      = actual_fty `i64`
                    }
                    ? == ( nurl_str_get fty 0 ) 37
                      { // Named type (starts with '%'). Only treat as struct
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
                            { // Single-pointer-handle struct (Vec, String,
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
                            { // Multi-field / non-pointer-f0 struct: heap-box
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
                              ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print sz_int ) ( nurl_print `)\n` )
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
                            ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print sz_int ) ( nurl_print `)\n` )
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
                        { // double → i64 via bitcast (payload slot is i64).
                          // The receiving ?? match arm does the inverse via
                          // bitcast i64→double when reconstructing the value.
                          : s db_bc ( nurl_cg_reg cg )
                          ( nurl_print `  ` ) ( nurl_print db_bc )
                          ( nurl_print ` = bitcast double ` ) ( nurl_print fval )
                          ( nurl_print ` to i64\n` )
                          = actual_fval db_bc
                          = actual_fty `i64`
                        }
                        {} // i64/i32: use as-is
              }
          }
          { // Check if this is actually an enum type
            // Extract type name from agg_ty (e.g., "%Slice" from "%Slice")
            : s type_name ``
            ? == ( nurl_str_get agg_ty 0 ) 37
              { // Named type starting with '%' - extract name
                : i end_pos 1
                ~ & < end_pos ( nurl_str_len agg_ty ) != ( nurl_str_get agg_ty end_pos ) 32 {
                  = end_pos + end_pos 1
                }
                = type_name ( nurl_str_slice agg_ty 1 end_pos )
              }
              { // Anonymous type like "{ i64*, i64 }" - not an enum
                = type_name ``
              }

            // Check if it's actually an enum by looking for __variants key
            : s variants_key ( nurl_str_cat type_name `__variants` )
            : s variants_entry ( nurl_sym_get syms variants_key )
            : b is_enum & != 0 ( nurl_str_len type_name ) != 0 ( nurl_str_len variants_entry )

            ? is_enum
              { // enum payload: convert values to ptr
                ? ( seq fty `i1` )
                  { // Convert boolean to i64, then to ptr
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
                    { // Convert integer to ptr
                      : s conv_reg ( nurl_cg_reg cg )
                      ( nurl_print `  ` ) ( nurl_print conv_reg )
                      ( nurl_print ` = inttoptr ` ) ( nurl_print fty ) ( nurl_print ` ` )
                      ( nurl_print fval ) ( nurl_print ` to ptr\n` )
                      = actual_fval conv_reg
                      = actual_fty `ptr`
                    }
                    ? | ( seq fty `sref` ) ( seq fty `i8*` )
                      { // Convert string to ptr
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = bitcast ` ) ( nurl_print fty ) ( nurl_print ` ` )
                        ( nurl_print fval ) ( nurl_print ` to ptr\n` )
                        = actual_fval conv_reg
                        = actual_fty `ptr`
                      }
                      ? == ( nurl_str_get fty 0 ) 123
                        { // Anonymous aggregate (e.g., { i1, i64 }): alloca + store + bitcast to ptr
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
                        ? == ( nurl_str_get fty 0 ) 37
                          { // Named struct handle (e.g. %Vec__Json, %String):
                            // extract field 0 (a pointer) and bitcast to ptr.
                            // Match-arm payload binding does the inverse via
                            // insertvalue. Skipped when the named type is an
                            // enum — enum variants get extractvalue+ptrtoint
                            // by the i64-tag branch above.
                            : s sname3 ( nurl_str_slice fty 1 - ( nurl_str_len fty ) 1 )
                            : s vlist3 ( nurl_sym_get syms ( nurl_str_cat sname3 `__variants` ) )
                            ? == 0 ( nurl_str_len vlist3 ) {
                              : s f0_ty3 ( nurl_sym_get syms ( nurl_str_cat3 sname3 `__idx_0` `__type` ) )
                              ? & != 0 ( nurl_str_len f0_ty3 )
                                   == ( nurl_str_get f0_ty3 - ( nurl_str_len f0_ty3 ) 1 ) 42
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
                                {} }
                              {}
                          }
                          {}
              }
              { // Regular struct: preserve field types as-is
                // No conversion needed - use original fval and fty
              }
          }
      }
      {}

    : s r    ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print r )
    ( nurl_print ` = insertvalue ` ) ( nurl_print agg_ty )
    ( nurl_print ` ` ) ( nurl_print result )
    ( nurl_print `, ` ) ( nurl_print actual_fty )
    ( nurl_print ` ` ) ( nurl_print actual_fval )
    ( nurl_print `, ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
    = result r
    = idx + idx 1
  }
  ( expect lex TT_RBRACE )       // consume '}'
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
  result
}

// ── Slice literal [ type | val* ] ─────────────────────────────────
// Allocates a heap array, stores values, returns { T*, i64 } slice struct.
// Example:  [ i | 10 20 30 ]  →  { i64* ptr, i64 3 }

@ gen_slice_literal i lex i syms i cg → s {
  ( nurl_lex_advance lex )                    // consume '['
  : s elem_ty ( parse_type lex )              // e.g. "i64"
  ( expect lex TT_PIPE )                      // consume '|'
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
  ( nurl_print sz_i ) ( nurl_print `)\n` )
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
  ? ( seq lt `i64` )    ^ `i`
  ? ( seq lt `i8` )     ^ `u`
  ? ( seq lt `i1` )     ^ `b`
  ? ( seq lt `double` ) ^ `f`
  ? ( seq lt `i8*` )    ^ `s`
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
        {} }
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
  ( nurl_print size_i64 ) ( nurl_print `)\n` )

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
      { // Store the alloca pointer itself — no load, no copy.
        = loaded var_alloca }
      { // Existing path: load the variable's current value.
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
  ( nurl_print `, label %` ) ( nurl_print continue_label ) ( nurl_print `\n` )

  // Deallocation block
  ( nurl_print dealloc_label ) ( nurl_print `:\n` )
  ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print env_ptr ) ( nurl_print `)\n` )
  ( nurl_print `  br label %` ) ( nurl_print continue_label ) ( nurl_print `\n` )

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
  ( nurl_print `) {\nentry:\n` )

  // Build closure body symtable: copy outer scope + add params + captured vars
  ( nurl_sym_push syms )
  : i body_syms syms
  // Shadow outer __owned_slices__ with empty list for the closure body
  ( nurl_sym_def body_syms `__owned_slices__` `` )
  // Defers don't cross closure boundaries — clear shadow too
  ( nurl_sym_def body_syms `__defer_top__` `` )

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
    = bp_types ( str_skip_word bp_types )
    = bp_names ( str_skip_word bp_names )
    = bpi + bpi 1
  }

  // Register captured variables via environment struct
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
          { // The loaded value IS the caller's alloca pointer.
            ( nurl_sym_def body_syms cap_name cap_type )
            ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__ptr` ) cap_val )
            ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__mutable` ) `1` ) }
          { // Existing path: alloca + store so the body sees a local.
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
  : s body_val ( gen_stmt lex body_syms cg )

  // Emit return
  ? == g_did_ret 0
    {
      ? ( seq ret_type `void` )
        { ( nurl_print `  ret void\n` ) }
        { ( nurl_print `  ret ` ) ( nurl_print ret_type ) ( nurl_print ` ` )
          ( nurl_print body_val ) ( nurl_print `\n` )
        }
    }
    {}
  ( nurl_print `}\n` )
  = g_did_ret outer_did_ret

  ( nurl_sym_pop syms )

  // Stop capturing and store as deferred closure function
  : s funcdef ( nurl_print_buf_stop )
  ( store_closure_func funcdef )

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
  : s vt  ( nurl_get_last_type )
  // T7: verify expression is opt or res type (must start with "{ i1, ")
  : b is_opt_res & >= ( nurl_str_len vt ) 6
                    ( seq ( nurl_str_slice vt 0 6 ) `{ i1, ` )
  ? ! is_opt_res
    { ( die lex ( nurl_str_cat `try operator \\ used on non-Result type: ` ( llvm_to_nurl vt ) ) ) }
    {}
  // T8: for res_type, verify error type matches enclosing function's error type
  : s call_nurl ( nurl_sym_get syms `__last_nurl_call__` )
  : s fn_nurl   ( nurl_sym_get syms `__fn_nurl_ret__` )
  ? & != 0 ( nurl_str_len call_nurl ) != 0 ( nurl_str_len fn_nurl )
    { ? ! ( seq call_nurl fn_nurl )
        { // extract error type (3rd word, e.g. "! i s" → "s")
          : s call_e ( str_first_word ( str_skip_word ( str_skip_word call_nurl ) ) )
          : s fn_e   ( str_first_word ( str_skip_word ( str_skip_word fn_nurl ) ) )
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
  : s lok   ( nurl_cg_lbl cg `try_ok` )
  : s lfail ( nurl_cg_lbl cg `try_fail` )
  ( nurl_print `  br i1 ` ) ( nurl_print tag )
  ( nurl_print `, label %` ) ( nurl_print lok )
  ( nurl_print `, label %` ) ( nurl_print lfail ) ( nurl_print `\n` )
  // Fail path: propagate the Err/None value, routing through defer chain if active.
  // For res_type: return val (preserves original error payload).
  // For opt_type: return zeroinitializer (None = { false, 0 }).
  ( emit ( nurl_str_cat lfail `:` ) )
  : s fn_rt ( nurl_sym_get syms `__fn_ret_ty__` )
  : s dtop  ( nurl_sym_get syms `__defer_top__` )
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
      ( nurl_print `  br label %` ) ( nurl_print dtop ) ( nurl_print `\n` )
    }
    { ? ( seq fn_rt `void` )
        { ( emiti `ret void` ) }
        { ( nurl_print `  ret ` ) ( nurl_print fn_rt )
          ( nurl_print ` ` ) ( nurl_print fail_val ) ( nurl_print `\n` )
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
  : b is_heapbox_enum   F
  : s f0_ty   ``
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
      ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print ubraw ) ( nurl_print `)\n` )
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
  ? ( seq lty `i64` )    ^ `i64`
  ? ( seq lty `double` ) ^ `f64`
  ? ( seq lty `i1` )     ^ `i1`
  ? ( seq lty `i8*` )    ^ `str`
  ? ( seq lty `void` )   ^ `void`
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
    : b is_ident | | != ( nurl_is_alpha ch ) 0 != ( nurl_is_digit ch ) 0 == ch 95
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

// gen_generic_fn_store: record a generic function declaration.
// Called when '[' is seen after the function name in gen_fn_decl.
// Stores source template in g_generic_syms; emits no IR.
@ gen_generic_fn_store i lex i syms s fname → v {
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
}

// compute_generic_ret_ty: determine return type of a generic instantiation
// without emitting IR. type_args: space-separated raw NURL type tokens.
@ compute_generic_ret_ty s fname s type_args → s {
  : s tparams ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
  : s gsrc    ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__gsrc` ) )
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
      // Reset the param roster before parsing — gen_fn_param appends
      // (name,type) pairs as `name\ttype|name\ttype|…` so
      // __alloca_struct_params can iterate them after `entry:` is
      // emitted and back struct-typed params with alloca slots.
      ( nurl_sym_def syms `__fn_params__` `` )
      // Guard against EOF too: without this, a malformed header that
      // never produces TT_ARROW (e.g. ASCII `->` instead of `→`) hangs
      // the compiler in an infinite loop, because gen_fn_param on EOF
      // cannot advance past the end.
      ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF {
        ( gen_fn_param lex syms params_str pct )
        = params_str ( nurl_get_last_type )
        = pct + pct 1
      }
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
      ( nurl_print `(` ) ( nurl_print params_str ) ( nurl_print `) {\n` )
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
                { ( nurl_print `  br label %` ) ( nurl_print dtop ) ( nurl_print `\n` ) }
                { ( mem_drop_owned syms cg skip )
                  ? != 0 g_auto_drop_strings
                    { ( mem_drop_owned_strings syms cg skip_str_ptr )
                      ( mem_drop_owned_struct_fields syms cg )
                      ( mem_drop_user_drops syms cg skip_user_ptr )
                    }
                    {}
                  ( emiti `ret void` ) }
            }
            {}
        }
        { ? == g_did_ret 0
            { ? != 0 ( nurl_str_len dtop )
                { ( nurl_print `  store ` ) ( nurl_print ret_ty ) ( nurl_print ` ` )
                  ( nurl_print last ) ( nurl_print `, ` ) ( nurl_print ret_ty )
                  ( nurl_print `* ` ) ( nurl_print ret_val_ptr ) ( nurl_print `\n` )
                  ( nurl_print `  br label %` ) ( nurl_print dtop ) ( nurl_print `\n` )
                }
                { ( mem_drop_owned syms cg skip )
                  ? != 0 g_auto_drop_strings
                    { ( mem_drop_owned_strings syms cg skip_str_ptr )
                      ( mem_drop_owned_struct_fields syms cg )
                      ( mem_drop_user_drops syms cg skip_user_ptr )
                    }
                    {}
                  ( nurl_print `  ret ` ) ( nurl_print ret_ty )
                  ( nurl_print ` ` ) ( nurl_print last ) ( nurl_print `\n` ) }
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
              ( nurl_print ` ` ) ( nurl_print rv ) ( nurl_print `\n` )
            }
            { ( emiti `ret void` ) }
        }
        {}
      ( emit `}` ) ( emit `` )
      ( emit_str_globals base_str g_str_idx )
      ( emit_closure_globals )
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
@ gen_fn_param i lex i syms s cur_params i pct → v {
  : s lt ( parse_type lex )
  ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s pname ( nurl_lex_val lex )
      ( nurl_lex_advance lex )
      ( nurl_sym_def syms pname lt )
      // Mark parameter as immutable by design
      ( nurl_sym_def syms ( nurl_str_cat pname `__param` ) `1` )
      // Append this param's name + LLVM type to the function's param
      // roster so gen_fn_decl_concrete can later (post-`entry:`) emit
      // alloca + store for struct params, enabling `= . p field val`
      // inside the body. Format: space-separated `name type name type ...`
      // since param types may contain spaces (`{ i1, i64 }`)? No —
      // closures decompose to `{ R(i8*…)*, i8* }` which DOES contain
      // commas + spaces. Use a pipe separator between (name,type) pairs.
      : s roster ( nurl_sym_get syms `__fn_params__` )
      : s pair ( nurl_str_cat3 pname `\t` lt )
      : s next ? == 0 ( nurl_str_len roster ) pair ( nurl_str_cat3 roster `|` pair )
      ( nurl_sym_def syms `__fn_params__` next )
      : s entry ( nurl_str_cat3 lt ` %` pname )
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
        ( nurl_sym_def syms
            ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) )
            ( nurl_str_int fidx ) )
        ( nurl_sym_def syms
            ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) )
            flt )
        ( nurl_sym_def syms
            ( nurl_str_cat3 sname `__idx_` ( nurl_str_cat ( nurl_str_int fidx ) `__type` ) )
            flt )
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
}

@ gen_const_decl s ty_tok b is_mutable i lex i syms → v {
  : s lt ( llvm_type ty_tok )
  ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s cname ( nurl_lex_val lex )
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

// ── FFI declaration: & `lib` @ name params → type ─────────────────
// Emits a `declare` for an external C function.

@ gen_ffi_decl i lex i syms → v {
  ( nurl_lex_advance lex )          // consume '&'
  ( nurl_lex_advance lex )          // skip library STR (linker concern, not IR)
  ( expect lex TT_AT )              // consume '@'
  : s fname ( nurl_lex_val lex )
  ( nurl_lex_advance lex )
  : s params_str ``
  : i pct 0
  ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF {
    : s lt ( parse_type lex )
    ? ( is_ident_tok ( nurl_lex_type lex ) ) { ( nurl_lex_advance lex ) } {}
    ? == pct 0
      { = params_str lt }
      { = params_str ( nurl_str_cat params_str ( nurl_str_cat `, ` lt ) ) }
    = pct + pct 1
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
  ( nurl_lex_advance lex )   // consume '|'
  : s ename ( nurl_lex_val lex )
  ( nurl_lex_advance lex )   // consume enum name
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
// When an alias is present, every top-level `@` function defined in the
// imported file is renamed in the file's source to `alias__name` before
// compilation. Callers can then reach those functions via the namespace
// syntax `alias::name`, which the lexer merges into a single IDENT
// `alias__name`. FFI declarations (`& "lib" @ name ...`), struct / enum /
// const names and trait/impl methods are NOT renamed in this iteration.

// collect_alias_targets: walk `src` and return the set of top-level `@`
// function names as a space-separated list. The FFI `@ name` that follows
// `& STR` is skipped, as are nested imports' optional alias idents.
@ collect_alias_targets s src s path → s {
  : i lx ( nurl_lex_new src path )
  : s names ``
  : i depth 0
  ~ != ( nurl_lex_type lx ) TT_EOF {
    : i tt ( nurl_lex_type lx )
    ? == tt TT_LBRACE
      { = depth + depth 1 ( nurl_lex_advance lx ) }
      { ? == tt TT_RBRACE
          { = depth - depth 1 ( nurl_lex_advance lx ) }
          { ? & == depth 0 == tt TT_AMP
              { // FFI: skip '& STR @ IDENT' so the FFI target name is not collected
                ( nurl_lex_advance lx )
                ? == ( nurl_lex_type lx ) TT_STR       { ( nurl_lex_advance lx ) } {}
                ? == ( nurl_lex_type lx ) TT_AT        { ( nurl_lex_advance lx ) } {}
                ? ( is_ident_tok ( nurl_lex_type lx ) ) { ( nurl_lex_advance lx ) } {}
              }
              { ? & == depth 0 == tt TT_DOLLAR
                  { // Nested import: skip path STR + optional alias IDENT
                    ( nurl_lex_advance lx )
                    ? == ( nurl_lex_type lx ) TT_STR       { ( nurl_lex_advance lx ) } {}
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
                      { ( nurl_lex_advance lx ) }
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
  : i in_string 0   // 1 while scanning inside a backtick-delimited string
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
          { : b is_id | | != ( nurl_is_alpha ch ) 0 != ( nurl_is_digit ch ) 0 == ch 95
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
  ( nurl_lex_advance lex )              // consume '$'
  : s path ( nurl_lex_val lex )
  ( nurl_lex_advance lex )              // consume path STR
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
      : i lex2 ( nurl_lex_new eff_src path )
      ( scan_fn_sigs lex2 syms )
      : i lex3 ( nurl_lex_new eff_src path )
      ( parse_program lex3 syms cg )
    }
}

// ── Generic instantiation flush (Group E) ────────────────────────────
// emit_one_instantiation: build and emit one monomorphised function.
@ emit_one_instantiation s fname s mangled s type_args i syms i cg → v {
  : s tparams ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
  : s gsrc    ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__gsrc` ) )
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
  : i lex2 ( nurl_lex_new full_src `<generic>` )
  ( gen_fn_decl lex2 syms cg )
}

// flush_deferred_instantiations: emit all queued generic instantiations.
// Re-reads count each iteration so transitive generics are also emitted.
@ flush_deferred_instantiations i syms i cg → v {
  : i k 0
  ~ < k ( nurl_str_to_int ( nurl_sym_get g_generic_syms `__deferred_count__` ) ) {
    : s base ( nurl_str_cat `__def` ( nurl_str_int k ) )
    : s fname     ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_fn` ) )
    : s mangled   ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_mn` ) )
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
  ( emit `declare i32  @puts(i8*)` )
  ( emit `declare i32  @printf(i8*, ...)` )
  ( emit `declare i8*  @malloc(i64)` )
  ( emit `declare void @free(i8*)` )
  ( emit `declare void @nurl_init(i32, i8**)` )
  ( emit `declare void @nurl_print(i8*)` )
  ( emit `declare void @nurl_eprint(i8*)` )
  ( emit `declare void @nurl_eprintln(i8*)` )
  ( emit `declare void @nurl_print_int(i64)` )
  ( emit `declare void @nurl_print_str(i8*)` )
  ( emit `declare void @nurl_print_bool(i1)` )
  ( emit `declare i64  @nurl_read_int()` )
  ( emit `declare i8*  @nurl_read_line()` )
  ( emit `declare i64  @nurl_stdin_eof()` )
  ( emit `declare void @nurl_flush_stdout()` )
  ( emit `declare void @nurl_flush_stderr()` )
  ( emit `declare i64  @nurl_str_len(i8*)` )
  ( emit `declare i64  @nurl_str_get(i8*, i64)` )
  ( emit `declare i64  @nurl_str_eq(i8*, i8*)` )
  ( emit `declare i64  @nurl_str_cmp(i8*, i8*)` )
  ( emit `declare i8*  @nurl_str_cat(i8*, i8*)` )
  ( emit `declare i8*  @nurl_str_cat3(i8*, i8*, i8*)` )
  ( emit `declare i8*  @nurl_str_cat4(i8*, i8*, i8*, i8*)` )
  ( emit `declare i8*  @nurl_str_int(i64)` )
  ( emit `declare i8*  @nurl_str_float(double)` )
  ( emit `declare i64  @nurl_str_to_int(i8*)` )
  ( emit `declare double @nurl_str_to_float(i8*)` )
  ( emit `declare i64    @nurl_parse_int_range(i8*, i64)` )
  ( emit `declare double @nurl_parse_float_range(i8*, i64)` )
  ( emit `declare i64    @nurl_memcmp_lex(i8*, i64, i8*, i64)` )
  ( emit `declare i64    @nurl_memmem_range(i8*, i64, i8*, i64)` )
  ( emit `declare i64    @nurl_csv_scan_cell(i8*, i64, i64)` )
  ( emit `declare i64    @nurl_csv_parse_arena(i8*, i64, i64, i64*, i64, i64*, i64*, i64, i64*, i64)` )
  ( emit `declare i64    @nurl_csv_n_rows_out()` )
  ( emit `declare i64    @nurl_csv_n_header_out()` )
  ( emit `declare i64    @nurl_csv_n_cells_out()` )
  ( emit `declare i64    @nurl_csv_scan_row_pairs(i8*, i64, i64, i64, i64*, i64)` )
  ( emit `declare i64    @nurl_csv_row_n_cells_out()` )
  ( emit `declare i64    @nurl_csv_row_next_pos_out()` )
  ( emit `declare i8*  @nurl_str_slice(i8*, i64, i64)` )
  ( emit `declare i64  @nurl_str_starts(i8*, i8*)` )
  ( emit `declare i64  @nurl_str_find(i8*, i8*)` )
  ( emit `declare i64  @nurl_map_new()` )
  ( emit `declare void @nurl_map_put(i64, i8*, i64)` )
  ( emit `declare i64  @nurl_map_get(i64, i8*)` )
  ( emit `declare i64  @nurl_map_has(i64, i8*)` )
  ( emit `declare void @nurl_map_del(i64, i8*)` )
  ( emit `declare i64  @nurl_map_size(i64)` )
  ( emit `declare void @nurl_map_free(i64)` )
  ( emit `declare i64  @nurl_is_alpha(i64)` )
  ( emit `declare i64  @nurl_is_digit(i64)` )
  ( emit `declare i64  @nurl_is_space(i64)` )
  ( emit `declare i64  @nurl_is_alnum_(i64)` )
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
  ( emit `declare i8*  @nurl_file_open(i8*, i8*)` )
  ( emit `declare void @nurl_file_write(i8*, i8*)` )
  ( emit `declare void @nurl_file_write_range(i8*, i8*, i64)` )
  ( emit `declare void @nurl_file_write_byte(i8*, i64)` )
  ( emit `declare void @nurl_file_close(i8*)` )
  ( emit `declare i8*  @nurl_file_read(i8*)` )
  ( emit `declare i64  @nurl_file_exists(i8*)` )
  ( emit `declare i64  @nurl_file_size(i8*)` )
  ( emit `declare void @nurl_file_del(i8*)` )
  ( emit `declare i8*  @nurl_read_file_safe(i8*)` )
  ( emit `declare i64  @nurl_write_file_safe(i8*, i8*, i8*)` )
  ( emit `declare i64  @nurl_dir_create(i8*)` )
  ( emit `declare i64  @nurl_dir_remove(i8*)` )
  ( emit `declare i64  @nurl_errno_kind()` )
  ( emit `declare i64  @nurl_str_ends(i8*, i8*)` )
  ( emit `declare double @nurl_sqrt(double)` )
  ( emit `declare double @nurl_fabs(double)` )
  ( emit `declare double @nurl_floor(double)` )
  ( emit `declare double @nurl_ceil(double)` )
  ( emit `declare double @nurl_round(double)` )
  ( emit `declare double @nurl_pow(double, double)` )
  ( emit `declare double @nurl_log(double)` )
  ( emit `declare double @nurl_exp(double)` )
  ( emit `declare double @nurl_sin(double)` )
  ( emit `declare double @nurl_cos(double)` )
  ( emit `declare double @nurl_tan(double)` )
  ( emit `declare double @nurl_atan2(double, double)` )
  ( emit `declare i64    @nurl_is_nan(double)` )
  ( emit `declare i64    @nurl_is_inf(double)` )
  ( emit `declare i64  @nurl_iabs(i64)` )
  ( emit `declare i64  @nurl_ipow(i64, i64)` )
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
  ( emit `declare i64  @nurl_log_level_get()` )
  ( emit `declare void @nurl_log_level_set(i64)` )
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
  ( emit `declare i8*  @nurl_sha256_hex(i8*)` )
  ( emit `declare i8*  @nurl_hmac_sha256_hex(i8*, i8*)` )
  ( emit `declare i64  @nurl_rand_u64()` )
  ( emit `declare i8*  @nurl_rand_bytes_hex(i64)` )
  ( emit `declare i8*  @nurl_read_file_bytes(i8*)` )
  ( emit `declare i64  @nurl_write_file_bytes(i8*, i8*, i64, i8*)` )
  ( emit `declare i64  @nurl_last_bytes_len()` )
  ( emit `declare i64  @nurl_tcp_listen(i8*, i64, i64)` )
  ( emit `declare i64  @nurl_tcp_accept(i64)` )
  ( emit `declare i64  @nurl_tcp_read(i64, i8*, i64)` )
  ( emit `declare i64  @nurl_tcp_write(i64, i8*, i64)` )
  ( emit `declare void @nurl_tcp_close(i64)` )
  ( emit `declare void @nurl_tcp_shutdown(i64)` )
  ( emit `declare i64  @nurl_tcp_err_kind(i64)` )
  ( emit `declare i8*  @nurl_tcp_peer_addr(i64)` )
  ( emit `declare void @nurl_tcp_set_timeout(i64, i64)` )
  ( emit `declare i64  @nurl_thread_spawn(i8*, i8*)` )
  ( emit `declare i64  @nurl_thread_join(i64)` )
  ( emit `declare void @nurl_thread_detach(i64)` )
  ( emit `declare i64  @nurl_mutex_new()` )
  ( emit `declare void @nurl_mutex_lock(i64)` )
  ( emit `declare void @nurl_mutex_unlock(i64)` )
  ( emit `declare void @nurl_mutex_free(i64)` )
  ( emit `declare i64  @nurl_cond_new()` )
  ( emit `declare void @nurl_cond_wait(i64, i64)` )
  ( emit `declare void @nurl_cond_signal(i64)` )
  ( emit `declare void @nurl_cond_broadcast(i64)` )
  ( emit `declare void @nurl_cond_free(i64)` )
  ( emit `declare void @nurl_signal_install_shutdown(i64)` )
  ( emit `declare void @nurl_signal_trigger_shutdown()` )
  ( emit `` )
}

// ── Pre-register runtime functions returning i8* ──────────────────

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
  ( nurl_sym_def syms `nurl_lex_val`       `i8*` )
  ( nurl_sym_def syms `nurl_lex_filename`  `i8*` )
  ( nurl_sym_def syms `nurl_lex_line_text` `i8*` )
  ( nurl_sym_def syms `nurl_diag_caret`    `i8*` )
  ( nurl_sym_def syms `nurl_cg_reg`        `i8*` )
  ( nurl_sym_def syms `nurl_cg_lbl`        `i8*` )
  ( nurl_sym_def syms `nurl_get_last_type` `i8*` )
  ( nurl_sym_def syms `nurl_sym_get`       `i8*` )
  ( nurl_sym_def syms `nurl_argv`          `i8*` )
  ( nurl_sym_def syms `nurl_argv_get`      `i8*` )
  ( nurl_sym_def syms `nurl_read_file`     `i8*` )
  ( nurl_sym_def syms `nurl_read_line`     `i8*` )
  ( nurl_sym_def syms `nurl_str_cat`       `i8*` )
  ( nurl_sym_def syms `nurl_str_cat3`      `i8*` )
  ( nurl_sym_def syms `nurl_str_cat4`      `i8*` )
  ( nurl_sym_def syms `nurl_str_int`       `i8*` )
  ( nurl_sym_def syms `nurl_str_float`    `i8*` )
  ( nurl_sym_def syms `nurl_str_slice`     `i8*` )
  // Phase 2B: mark allocating string runtime calls as returning OWNED str.
  // Gated on g_auto_drop_strings — off by default to keep the compiler's
  // own source compilable without false-positive auto-drops. The sideband
  // `__ret_owned` carries kind: "1" = slice (Phase 2A), "str" = string.
  ? != 0 g_auto_drop_strings
    { ( nurl_sym_def syms `nurl_str_cat__ret_owned`   `str` )
      ( nurl_sym_def syms `nurl_str_cat3__ret_owned`  `str` )
      ( nurl_sym_def syms `nurl_str_cat4__ret_owned`  `str` )
      ( nurl_sym_def syms `nurl_str_int__ret_owned`   `str` )
      ( nurl_sym_def syms `nurl_str_float__ret_owned` `str` )
      ( nurl_sym_def syms `nurl_str_slice__ret_owned` `str` )
      ( nurl_sym_def syms `nurl_read_file__ret_owned` `str` )
      ( nurl_sym_def syms `nurl_read_line__ret_owned` `str` )
    }
    {}
  ( nurl_sym_def syms `malloc`             `i8*` )
  ( nurl_sym_def syms `nurl_malloc`        `i8*` )
  ( nurl_sym_def syms `nurl_alloc`         `i8*` )
  ( nurl_sym_def syms `nurl_zalloc`        `i8*` )
  ( nurl_sym_def syms `nurl_realloc`       `i8*` )
  // file I/O
  ( nurl_sym_def syms `nurl_file_open`        `i8*` )
  ( nurl_sym_def syms `nurl_file_write`       `void` )
  ( nurl_sym_def syms `nurl_file_write_range` `void` )
  ( nurl_sym_def syms `nurl_file_write_byte`  `void` )
  ( nurl_sym_def syms `nurl_file_close`       `void` )
  ( nurl_sym_def syms `nurl_file_read`   `i8*` )
  ( nurl_sym_def syms `nurl_file_exists` `i64` )
  ( nurl_sym_def syms `nurl_file_size`   `i64` )
  ( nurl_sym_def syms `nurl_file_del`    `void` )
  // non-fatal fs API used by stdlib/std/fs.nu — raw is an i8* the caller
  // must `nurl_free` after copying (see read_file). Intentionally NOT
  // marked __ret_owned to avoid double-free against the manual free.
  ( nurl_sym_def syms `nurl_read_file_safe`  `i8*` )
  ( nurl_sym_def syms `nurl_write_file_safe` `i64` )
  ( nurl_sym_def syms `nurl_dir_create`      `i64` )
  ( nurl_sym_def syms `nurl_dir_remove`      `i64` )
  ( nurl_sym_def syms `nurl_errno_kind`      `i64` )
  // double-returning runtime functions
  ( nurl_sym_def syms `nurl_lex_fnum`     `double` )
  ( nurl_sym_def syms `nurl_str_to_float` `double` )
  ( nurl_sym_def syms `nurl_str_float_value` `double` )
  ( nurl_sym_def syms `nurl_parse_float_range` `double` )
  ( nurl_sym_def syms `nurl_sqrt`  `double` )
  ( nurl_sym_def syms `nurl_fabs`  `double` )
  ( nurl_sym_def syms `nurl_floor` `double` )
  ( nurl_sym_def syms `nurl_ceil`  `double` )
  ( nurl_sym_def syms `nurl_round` `double` )
  ( nurl_sym_def syms `nurl_pow`   `double` )
  ( nurl_sym_def syms `nurl_log`   `double` )
  ( nurl_sym_def syms `nurl_exp`   `double` )
  ( nurl_sym_def syms `nurl_sin`   `double` )
  ( nurl_sym_def syms `nurl_cos`   `double` )
  ( nurl_sym_def syms `nurl_tan`   `double` )
  ( nurl_sym_def syms `nurl_atan2` `double` )
  // i64-returning math/time/parse helpers
  ( nurl_sym_def syms `nurl_is_nan`            `i64` )
  ( nurl_sym_def syms `nurl_is_inf`            `i64` )
  ( nurl_sym_def syms `nurl_iabs`              `i64` )
  ( nurl_sym_def syms `nurl_ipow`              `i64` )
  ( nurl_sym_def syms `nurl_str_to_float_safe` `i64` )
  ( nurl_sym_def syms `nurl_parse_int_range`   `i64` )
  ( nurl_sym_def syms `nurl_memcmp_lex`        `i64` )
  ( nurl_sym_def syms `nurl_memmem_range`      `i64` )
  ( nurl_sym_def syms `nurl_csv_scan_cell`     `i64` )
  ( nurl_sym_def syms `nurl_csv_parse_arena`   `i64` )
  ( nurl_sym_def syms `nurl_csv_n_rows_out`    `i64` )
  ( nurl_sym_def syms `nurl_csv_n_header_out`  `i64` )
  ( nurl_sym_def syms `nurl_csv_n_cells_out`   `i64` )
  ( nurl_sym_def syms `nurl_csv_scan_row_pairs`    `i64` )
  ( nurl_sym_def syms `nurl_csv_row_n_cells_out`   `i64` )
  ( nurl_sym_def syms `nurl_csv_row_next_pos_out`  `i64` )
  ( nurl_sym_def syms `nurl_now_ms`            `i64` )
  ( nurl_sym_def syms `nurl_now_seconds`       `i64` )
  ( nurl_sym_def syms `nurl_monotonic_ns`      `i64` )
  ( nurl_sym_def syms `nurl_sleep_ms`          `void` )
  // CLI tooling — i8*-returning calls return heap-owned strings (caller frees)
  ( nurl_sym_def syms `nurl_env_get`         `i8*` )
  ( nurl_sym_def syms `nurl_cwd`             `i8*` )
  ( nurl_sym_def syms `nurl_read_all_stdin`  `i8*` )
  ( nurl_sym_def syms `nurl_dir_list_next`   `i8*` )
  ( nurl_sym_def syms `nurl_env_set`         `i64` )
  ( nurl_sym_def syms `nurl_env_unset`       `i64` )
  ( nurl_sym_def syms `nurl_chdir`           `i64` )
  ( nurl_sym_def syms `nurl_dir_list_open`   `i64` )
  ( nurl_sym_def syms `nurl_dir_list_close`  `void` )
  // HTTP runtime helpers (libcurl bridge — see runtime.c §14).
  // Body / header accessors return BORROWED i8* views into the
  // response struct, so they intentionally do NOT carry the
  // __ret_owned=str marker — the caller MUST NOT auto-free them.
  ( nurl_sym_def syms `nurl_http_perform_full`        `i64` )
  ( nurl_sym_def syms `nurl_http_perform_full_to`     `i64` )
  ( nurl_sym_def syms `nurl_http_response_status`     `i64` )
  ( nurl_sym_def syms `nurl_http_response_err_kind`   `i64` )
  ( nurl_sym_def syms `nurl_http_response_body`       `i8*` )
  ( nurl_sym_def syms `nurl_http_response_body_len`   `i64` )
  ( nurl_sym_def syms `nurl_http_response_header_count` `i64` )
  ( nurl_sym_def syms `nurl_http_response_header_name`  `i8*` )
  ( nurl_sym_def syms `nurl_http_response_header_value` `i8*` )
  ( nurl_sym_def syms `nurl_http_response_free`       `void` )
  // HTTP streaming (runtime.c §14b). Pull-based — NURL drives one
  // chunk at a time. `nurl_http_stream_next` returns a heap-owned
  // i8* (NULL on EOF/error); mark it as owned so auto-drop wraps it.
  ( nurl_sym_def syms `nurl_http_stream_open_to`      `i64` )
  ( nurl_sym_def syms `nurl_http_stream_next`         `i8*` )
  ( nurl_sym_def syms `nurl_http_stream_next__ret_owned` `str` )
  ( nurl_sym_def syms `nurl_http_stream_status`       `i64` )
  ( nurl_sym_def syms `nurl_http_stream_err_kind`     `i64` )
  ( nurl_sym_def syms `nurl_http_stream_close`        `void` )
  ( nurl_sym_def syms `nurl_http_stream_pump_headers` `i64` )
  ( nurl_sym_def syms `nurl_http_stream_header_count` `i64` )
  ( nurl_sym_def syms `nurl_http_stream_header_name`  `i8*` )
  ( nurl_sym_def syms `nurl_http_stream_header_value` `i8*` )
  // log level (process-wide)
  ( nurl_sym_def syms `nurl_log_level_get`            `i64` )
  ( nurl_sym_def syms `nurl_log_level_set`            `void` )
  // process execution (runtime §16). Output buffers are BORROWED views
  // into the runtime-owned NurlProcResult — do NOT mark __ret_owned.
  ( nurl_sym_def syms `nurl_proc_run`         `i64` )
  ( nurl_sym_def syms `nurl_proc_exit_code`   `i64` )
  ( nurl_sym_def syms `nurl_proc_err_kind`    `i64` )
  ( nurl_sym_def syms `nurl_proc_stdout`      `i8*` )
  ( nurl_sym_def syms `nurl_proc_stderr`      `i8*` )
  ( nurl_sym_def syms `nurl_proc_stdout_len`  `i64` )
  ( nurl_sym_def syms `nurl_proc_stderr_len`  `i64` )
  ( nurl_sym_def syms `nurl_proc_free`        `void` )
  // process spawn / duplex stdio (runtime §16b). read_line returns a
  // BORROWED i8* view into the child's internal line buffer (reused on
  // the next call) — do NOT mark __ret_owned. Callers copy via
  // string_from to materialise an owned String.
  ( nurl_sym_def syms `nurl_proc_spawn`             `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_err_kind`    `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_pid`         `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_write`       `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_close_stdin` `void` )
  ( nurl_sym_def syms `nurl_proc_spawn_read_line`   `i8*` )
  ( nurl_sym_def syms `nurl_proc_spawn_read_line_len` `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_eof`         `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_last_io_err` `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_wait`        `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_kill`        `i64` )
  ( nurl_sym_def syms `nurl_proc_spawn_free`        `void` )
  // crypto (runtime §17). The hex-digest returns are heap-owned i8*
  // (caller frees via nurl_free); not auto-marked __ret_owned because
  // the wrappers in stdlib/std/hash.nu and stdlib/std/random.nu do
  // their own copy + free.
  ( nurl_sym_def syms `nurl_sha256_hex`       `i8*` )
  ( nurl_sym_def syms `nurl_hmac_sha256_hex`  `i8*` )
  ( nurl_sym_def syms `nurl_rand_u64`         `i64` )
  ( nurl_sym_def syms `nurl_rand_bytes_hex`   `i8*` )
  // Binary file I/O (runtime §4 extension). Read returns a heap buffer +
  // sideband length via nurl_last_bytes_len; not __ret_owned-marked
  // because stdlib/std/fs.nu reads the bytes into a Vec[u] and frees
  // the buffer manually.
  ( nurl_sym_def syms `nurl_read_file_bytes`  `i8*` )
  ( nurl_sym_def syms `nurl_write_file_bytes` `i64` )
  ( nurl_sym_def syms `nurl_last_bytes_len`   `i64` )
  // TCP sockets (runtime §18). Handles are i64-cast heap pointers; the
  // peer-addr accessor returns a BORROWED view into the handle struct,
  // so it is intentionally NOT __ret_owned-marked (caller copies via
  // string_from when a long-lived String is required).
  ( nurl_sym_def syms `nurl_tcp_listen`       `i64` )
  ( nurl_sym_def syms `nurl_tcp_accept`       `i64` )
  ( nurl_sym_def syms `nurl_tcp_read`         `i64` )
  ( nurl_sym_def syms `nurl_tcp_write`        `i64` )
  ( nurl_sym_def syms `nurl_tcp_close`        `void` )
  ( nurl_sym_def syms `nurl_tcp_shutdown`     `void` )
  ( nurl_sym_def syms `nurl_tcp_err_kind`     `i64` )
  ( nurl_sym_def syms `nurl_tcp_peer_addr`    `i8*` )
  ( nurl_sym_def syms `nurl_tcp_set_timeout`  `void` )
  // Thread / mutex / condvar (runtime §19). Handles are i64-cast heap
  // pointers — same convention as TCP. spawn takes raw fn/env i8*
  // pointers extracted from a NURL closure via `# *u f 0|1`.
  ( nurl_sym_def syms `nurl_thread_spawn`     `i64` )
  ( nurl_sym_def syms `nurl_thread_join`      `i64` )
  ( nurl_sym_def syms `nurl_thread_detach`    `void` )
  ( nurl_sym_def syms `nurl_mutex_new`        `i64` )
  ( nurl_sym_def syms `nurl_mutex_lock`       `void` )
  ( nurl_sym_def syms `nurl_mutex_unlock`     `void` )
  ( nurl_sym_def syms `nurl_mutex_free`       `void` )
  ( nurl_sym_def syms `nurl_cond_new`         `i64` )
  ( nurl_sym_def syms `nurl_cond_wait`        `void` )
  ( nurl_sym_def syms `nurl_cond_signal`      `void` )
  ( nurl_sym_def syms `nurl_cond_broadcast`   `void` )
  ( nurl_sym_def syms `nurl_cond_free`        `void` )
  ( nurl_sym_def syms `nurl_signal_install_shutdown` `void` )
  ( nurl_sym_def syms `nurl_signal_trigger_shutdown` `void` )
  // void runtime functions
  ( nurl_sym_def syms `nurl_print`         `void` )
  ( nurl_sym_def syms `nurl_eprint`        `void` )
  ( nurl_sym_def syms `nurl_eprintln`      `void` )
  ( nurl_sym_def syms `nurl_print_int`     `void` )
  ( nurl_sym_def syms `nurl_print_str`     `void` )
  ( nurl_sym_def syms `nurl_print_bool`    `void` )
  ( nurl_sym_def syms `nurl_lex_advance`   `void` )
  ( nurl_sym_def syms `nurl_sym_def`       `void` )
  ( nurl_sym_def syms `nurl_sym_push`      `void` )
  ( nurl_sym_def syms `nurl_sym_pop`       `void` )
  ( nurl_sym_def syms `nurl_cg_reset`      `void` )
  ( nurl_sym_def syms `nurl_set_last_type` `void` )
  ( nurl_sym_def syms `nurl_exit`          `void` )
  ( nurl_sym_def syms `nurl_flush_stdout`  `void` )
  ( nurl_sym_def syms `nurl_flush_stderr`  `void` )
  ( nurl_sym_def syms `nurl_stdin_eof`     `i64` )
  ( nurl_sym_def syms `free`               `void` )
  ( nurl_sym_def syms `nurl_free`          `void` )
  ( nurl_sym_def syms `nurl_map_put`       `void` )
  ( nurl_sym_def syms `nurl_map_del`       `void` )
  ( nurl_sym_def syms `nurl_map_free`      `void` )
  ( nurl_sym_def syms `nurl_memcpy`        `void` )
  ( nurl_sym_def syms `nurl_poke`          `void` )
  // output buffering
  ( nurl_sym_def syms `nurl_print_buf_start` `void` )
  ( nurl_sym_def syms `nurl_print_buf_stop`  `i8*` )
  ( nurl_sym_def syms `nurl_print_buf_reset` `void` )
  // lexer position save/restore
  ( nurl_sym_def syms `nurl_lex_cur_start` `i64` )
  ( nurl_sym_def syms `nurl_lex_src_slice` `i8*` )
  ( nurl_sym_def syms `nurl_lex_set_pos`   `void` )
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
      { ( nurl_lex_advance lex )   // skip '@'
        ? ( is_ident_tok ( nurl_lex_type lex ) )
          { : s mname ( nurl_lex_val lex )
            ( nurl_lex_advance lex )    // consume method name
            : i sig_start ( nurl_lex_cur_start lex )
            // Skip params / → / ret_ty until we hit '{' (body), next '@',
            // or '}' (end of trait).
            ~ & & != ( nurl_lex_type lex ) TT_LBRACE
                  != ( nurl_lex_type lex ) TT_AT
                  != ( nurl_lex_type lex ) TT_RBRACE {
              ( nurl_lex_advance lex )
            }
            ? == ( nurl_lex_type lex ) TT_LBRACE
              { // Default method: consume the body block and capture raw source.
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
              {} // header only — required method, no template to store
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
  : s tparam    ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__tparam` ) )
  : s defaults  ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__defaults` ) )
  ~ != 0 ( nurl_str_len defaults ) {
    : s mname ( str_first_word defaults )
    = defaults ( str_skip_word defaults )
    ? ( str_contains_word provided mname )
      {} // explicitly overridden by impl
      { : s src ( nurl_sym_get g_trait_syms
                  ( nurl_str_cat tname ( nurl_str_cat `__` ( nurl_str_cat mname `__src` ) ) ) )
        : s subst ? != 0 ( nurl_str_len tparam )
          ( subst_source_raw src tparam impl_nurl )
          src
        : s ret_ty ( trait_default_ret subst )
        : s key ( nurl_str_cat mname ( nurl_str_cat `##` impl_llvm ) )
        ( nurl_sym_def g_impl_ret_syms  key ret_ty )
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
    { // trait: remember its type param and scan for default methods
      ( nurl_sym_def g_trait_syms ( nurl_str_cat tname `__tparam` ) tparam )
      ( scan_trait_body lex tname )
    }
    { // impl_decl: read implementing type, then scan methods
      : s impl_nurl ( capture_impl_nurl_name lex )
      : s impl_llvm ( parse_type lex )           // e.g. "i64", "i8*", "%Point"
      : s impl_mangle ( mangle_type impl_llvm )
      ( expect lex TT_LBRACE )
      : s provided ``
      ~ != ( nurl_lex_type lex ) TT_RBRACE {
        ? == ( nurl_lex_type lex ) TT_AT
          { ( nurl_lex_advance lex )   // skip '@'
            ? ( is_ident_tok ( nurl_lex_type lex ) )
              { : s mname ( nurl_lex_val lex )
                ( nurl_lex_advance lex )    // skip method name
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
                    ( nurl_sym_def g_impl_ret_syms  key ret_ty )
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
  : s tparam   ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__tparam` ) )
  : s defaults ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__defaults` ) )
  ~ != 0 ( nurl_str_len defaults ) {
    : s mname ( str_first_word defaults )
    = defaults ( str_skip_word defaults )
    ? ( str_contains_word provided mname )
      {} // overridden: impl's concrete method already emitted
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
    { ( skip_balanced lex ) }   // trait: skip whole block, no IR
    { // impl_decl: read implementing type, emit methods with mangled names
      : s impl_nurl   ( capture_impl_nurl_name lex )
      : s impl_llvm   ( parse_type lex )
      : s impl_mangle ( mangle_type impl_llvm )
      ( expect lex TT_LBRACE )
      : s provided ``
      ~ != ( nurl_lex_type lex ) TT_RBRACE {
        ? == ( nurl_lex_type lex ) TT_AT
          { ( nurl_lex_advance lex )   // skip '@'
            ? ( is_ident_tok ( nurl_lex_type lex ) )
              { : s mname ( nurl_lex_val lex )
                ( nurl_lex_advance lex )    // skip method name
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
  ( nurl_lex_advance lex )    // consume '('
  : s sname ( nurl_lex_val lex )
  ( nurl_lex_advance lex )    // consume Name
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
        ( nurl_lex_advance lex )   // past '('
        : s cand ( nurl_lex_val lex )
        : s tparams ( nurl_sym_get g_generic_struct_syms ( nurl_str_cat cand `__stparams` ) )
        ? != 0 ( nurl_str_len tparams ) {
          ( nurl_lex_advance lex )   // past cand ident
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
        : s path ( nurl_lex_val lex )
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

// scan_fn_sigs: register return types of all @ and & declarations.
@ scan_fn_sigs i lex i syms → v {
  ~ != ( nurl_lex_type lex ) TT_EOF {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_AT
      { ( nurl_lex_advance lex )
        ? ( is_ident_tok ( nurl_lex_type lex ) )
          { : s fname ( nurl_lex_val lex )
            ( nurl_lex_advance lex )
            // Generic function [T U ...]: skip type params, mark as generic.
            // Slice type param [type name]: treat like regular params (not generic).
            // Must match the disambiguation in gen_fn_decl: accept IDENT *or*
            // BOOL for the param name (the bare letter `T` lexes as TT_BOOL),
            // and require ']' immediately after 1 or 2 param names.
            : b at_lbrack == ( nurl_lex_type lex ) TT_LBRACK
            : i p1s ? at_lbrack ( nurl_lex_peek_type lex )  0
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
                ( nurl_lex_advance lex )   // consume ']'
                ( nurl_sym_def syms ( nurl_str_cat fname `__generic` ) `1` )
                ( skip_balanced lex )
              }
              { ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF
                  { ( nurl_lex_advance lex ) }
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
          { ( nurl_lex_advance lex )   // skip '$'
            : s path ( nurl_lex_val lex )
            ( nurl_lex_advance lex )   // skip path STR
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
                ( scan_fn_sigs lex2 syms )
              }
          }

      // ffi_decl: & STR @ name params → type  (no body block to skip)
      ? == tt TT_AMP
        { ( nurl_lex_advance lex )   // skip '&'
          ( nurl_lex_advance lex )   // skip library STR
          ( nurl_lex_advance lex )   // skip '@'
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

// ── Top-level loop ─────────────────────────────────────────────────

@ parse_program i lex i syms i cg → v {
  ~ != ( nurl_lex_type lex ) TT_EOF {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_AT      { ( gen_fn_decl lex syms cg ) }
    ? == tt TT_COLON   { ( gen_const_or_struct lex syms ) }
    ? == tt TT_AMP     { ( gen_ffi_decl lex syms ) }
    ? == tt TT_DOLLAR  { ( gen_import_decl lex syms cg ) }
    ? == tt TT_PERCENT { ( gen_trait_or_impl lex syms cg ) }
    { ( nurl_lex_advance lex ) }
  }
}

// ── Entry point ────────────────────────────────────────────────────

@ main → v {
  ? != ( nurl_argc ) 2
    { ( nurl_eprintln `usage: nurlc <file.nu>` ) ( nurl_exit 1 ) }
    {}
  : s path ( nurl_argv 1 )
  : s src  ( nurl_read_file path )
  : s marker ( nurl_str_cat `@@nurl-disable` `-autodrop-strings@@` )
  ? >= ( nurl_str_find src marker ) 0
    { = g_auto_drop_strings 0 }
    {}
  : i syms ( nurl_sym_new )
  : i cg   ( nurl_cg_new )
  = g_str_syms ( nurl_sym_new )
  = g_generic_syms ( nurl_sym_new )
  = g_generic_struct_syms ( nurl_sym_new )
  = g_struct_inst_syms    ( nurl_sym_new )
  ( nurl_sym_def g_generic_syms `__deferred_count__` `0` )
  = g_impl_ret_syms  ( nurl_sym_new )
  = g_impl_name_syms ( nurl_sym_new )
  = g_trait_syms     ( nurl_sym_new )
  = g_res_type_syms  ( nurl_sym_new )
  = g_closure_defs        ( nurl_sym_new )
  = g_closure_types       ( nurl_sym_new )
  = g_type_count          0
  = g_func_count          0
  = g_closure_emit_base   0
  = g_type_emit_base      0
  ( emit_header )
  ( init_syms syms )
  : i lex0 ( nurl_lex_new src path )
  ( scan_generic_structs lex0 syms )
  : i lex1 ( nurl_lex_new src path )
  ( scan_fn_sigs lex1 syms )
  : i lex  ( nurl_lex_new src path )
  ( parse_program lex syms cg )
  // Emit all deferred generic instantiations collected during compilation.
  ( flush_deferred_instantiations syms cg )
}

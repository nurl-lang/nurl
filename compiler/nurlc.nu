// nurlc.nu — NURL compiler written in NURL.
// Grammar: v2.3
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
: i TT_OROR 46  // `||` — short-circuit logical OR  (binary, bool only)
: i TT_ANDAND 47  // `&&` — short-circuit logical AND (binary, bool only)

// ── Abort helpers ─────────────────────────────────────────────────

// Multi-error mode (rustc-style): while parse_program's per-declaration
// recovery frame is active (g_diag_recover_active), `die` prints its
// diagnostic and then PANICS with the __nurlc_diag__ sentinel instead of
// exiting — parse_program catches it, resyncs the lexer to the next
// top-level declaration, and keeps going, so one run reports many errors.
// Outside a recovery frame (the scan pre-passes, deferred flush stages)
// `die` stays fail-fast exit(1). Capped at NURLC_MAX_ERRORS so a cascade
// can't scroll forever; the emitted IR after the first error is garbage,
// but the non-zero exit makes every caller discard it.
: ~ i g_err_count 0
: ~ i g_diag_recover_active 0
: i NURLC_MAX_ERRORS 20

// die → __diag_abort: print-position variants share this exit/panic tail.
@ __diag_abort → v {
    ? != g_diag_recover_active 0
    { = g_err_count + g_err_count 1
        ? >= g_err_count NURLC_MAX_ERRORS
        { ( nurl_eprintln ( nurl_str_cat3 `error: too many errors (`
            ( nurl_str_int g_err_count ) `) — stopping here` ) )
            ( nurl_exit 1 ) }
        {}
        ( nurl_panic `__nurlc_diag__` )
    }
    {}
    ( nurl_exit 1 )
}

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
    ( __diag_abort )
}

// die_at: a fatal diagnostic for a deferred (post-scan) check that has only a
// stored "file:line" location, not a live lexer — so no column, caret, or
// source-line echo, but the same parseable "loc: msg" prefix. Used by the
// supertrait-obligation sweep, which runs after every impl in the program has
// been registered and so cannot point at a single lexer position.
@ die_at s loc s msg → v {
    ( nurl_eprintln ( nurl_str_cat3 loc `: ` msg ) )
    ( __diag_abort )
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

// die_if_void: the void/unit literal — produced ONLY by a bare type keyword
// `v` used in value position (gen_ident returns the literal value `void`) —
// has no representable SSA value and must never reach an operator, complement,
// or logical-not. Such a use used to lower to `add void void, …` /
// `xor void void, -1`: IR that nurlc emitted with status 0 and only clang
// later rejected ("void type only allowed for function results"). Reject it at
// the source so the trap is a NURL diagnostic.
//
// The check is on the operand VALUE, not its NURL type: a `v`-returning CALL or
// a void-valued block yields a real register whose type is `void` but whose
// value is a valid SSA name — and the consuming instruction takes its type
// from the other (typed) operand, so that IR is well-formed. Only the bare `v`
// keyword emits the literal value `void`, which is what breaks. `ctx` names the
// consuming construct.
@ die_if_void i lex s val s ctx → v {
    ? ( seq val `void` )
    { ( die lex ( nurl_str_cat ctx ` operand is the void/unit value 'v' — a bare type keyword yields no value and cannot be used here` ) ) }
    {}
}

// Record where a binding was declared, so a later "cannot assign to
// immutable …" diagnostic can point the author at the exact line to
// add `~` to. Keyed off the binding name; declfile carries the source
// path because a global may be assigned from a different file than the
// one that declared it.
@ rec_decl_loc i syms s name i line i lex → v {
    ( nurl_sym_def syms ( nurl_str_cat name `__declline` ) ( nurl_str_int line ) )
    ( nurl_sym_def syms ( nurl_str_cat name `__declfile` ) ( nurl_lex_filename lex ) )
}

@ expect i lex i tt → v {
    ? != ( nurl_lex_type lex ) tt
    { ( die lex ( nurl_str_cat3
        ( nurl_str_cat `expected ` ( __tok_label tt `` ) )
        ` but found `
        ( __tok_label ( nurl_lex_type lex ) ( nurl_lex_val lex ) ) ) ) }
    {}
    ( nurl_lex_advance lex )
}

// is_ident_tok: true if token type is IDENT or TYPE_KW.
@ is_ident_tok i tt → b {
    | == tt TT_IDENT == tt TT_TYPE_KW
}

// Normalise an integer-literal's SOURCE SPELLING to a decimal string:
// `0x…` / `0b…` → decimal, everything else passed through verbatim.
// Used wherever a pattern's literal token text is emitted straight into
// LLVM IR (match int-patterns, enum field-constraints) — LLVM reads a
// `0x…` constant as a hex FLOAT, so the spelling must be converted. The
// lexer's parsed inum is unreliable here (it is overwritten by the
// parser's lookahead peeks), so we re-parse the spelling instead.
@ __norm_int_lit s txt → s {
    : i n ( nurl_str_len txt )
    ? < n 3 { ^ txt } {}
    ? != ( nurl_str_get txt 0 ) 48 { ^ txt } {}  // not leading '0'
    : i c1 ( nurl_str_get txt 1 )
    ? | == c1 120 == c1 88 {  // 0x / 0X
        : ~ i acc 0
        : ~ i i 2
        ~ < i n { = acc + * acc 16 ( __lx_hex_val ( nurl_str_get txt i ) ) = i + i 1 }
        ^ ( nurl_str_int acc )
    } {}
    ? | == c1 98 == c1 66 {  // 0b / 0B
        : ~ i acc 0
        : ~ i i 2
        ~ < i n { = acc + * acc 2 - ( nurl_str_get txt i ) 48 = i + i 1 }
        ^ ( nurl_str_int acc )
    } {}
    ^ txt
}

// is_type_start: true if tt can start a type expression.
@ is_type_start i tt → b {
    | == tt TT_TYPE_KW | == tt TT_IDENT | == tt TT_STAR
    | == tt TT_QUEST | == tt TT_QUESTQUEST | == tt TT_LBRACK | == tt TT_BANG
    | == tt TT_LPAREN == tt TT_PIPE
}

// seq: string equality returning b (bool).
@ seq s a s b → b {
    != 0 ( nurl_str_eq a b )
}

// ── Res-type NURL tracking (must be declared before parse_type_res) ──
// g_res_type_syms is initialized to a new sym handle in main().
// parse_type_res stores "__last_res_nurl__" and "__last_res_err_llvm__" here.
: ~ i g_res_type_syms 0

// ── Type parsing ──────────────────────────────────────────────────

@ llvm_type s ty → s {
    ? ( seq ty `i` ) `i64`
    ? ( seq ty `u` ) `u8`  // unsigned 8-bit byte
    ? ( seq ty `f` ) `double`
    ? ( seq ty `b` ) `i1`
    ? ( seq ty `s` ) `i8*`
    ? ( seq ty `v` ) `void`
    // Fixed-size integer types (grammar v1.8). The INTERNAL type repr
    // carries signedness (A1): `u`/`u16`/`u32`/`u64` map to the
    // first-class unsigned internal types `u8`/`u16`/`u32`/`u64`,
    // distinct from `i8`..`i64` end to end. They lower to the LLVM
    // i-types only at the IR-emission boundary via `nurl_llty`.
    ? ( seq ty `i8` ) `i8`
    ? ( seq ty `i16` ) `i16`
    ? ( seq ty `i32` ) `i32`
    ? ( seq ty `i64` ) `i64`
    ? ( seq ty `u16` ) `u16`
    ? ( seq ty `u32` ) `u32`
    ? ( seq ty `u64` ) `u64`
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

// ── A1: signedness lives IN the type representation ─────────────────
// The internal type language is LLVM's plus four first-class unsigned
// scalar types `u8` / `u16` / `u32` / `u64` (source `u` → `u8`). They stay
// distinct from `i8`..`i64` end to end — through the last-type channel,
// binding/param/field/payload/return metadata, phi joins, and monomorph
// mangles — and lower to the LLVM i-types only at the IR-emission
// boundary via `nurl_llty`. This replaces the former `__last_unsigned__`
// flag side-channel entirely: a value's signedness is a fact about its
// type, so it can no longer go stale or be forgotten at a producing site.

// ty_is_unsigned: is an INTERNAL type string one of the unsigned scalars?
@ ty_is_unsigned s t → b {
    ? ( seq t `u8` ) { ^ T } {}
    ? ( seq t `u16` ) { ^ T } {}
    ? ( seq t `u32` ) { ^ T } {}
    ? ( seq t `u64` ) { ^ T } {}
    ^ F
}

// ty_to_unsigned: unsigned spelling of a signed scalar int type.
// Identity for everything else (already-unsigned, floats, pointers,
// aggregates). Used where a join must keep unsignedness contributed by
// the OTHER operand/arm (binop results, `?`-phi joins).
@ ty_to_unsigned s t → s {
    ? ( seq t `i8` ) { ^ # s ( strdup `u8` ) } {}
    ? ( seq t `i16` ) { ^ # s ( strdup `u16` ) } {}
    ? ( seq t `i32` ) { ^ # s ( strdup `u32` ) } {}
    ? ( seq t `i64` ) { ^ # s ( strdup `u64` ) } {}
    ^ # s ( strdup t )
}

// __llty_word_at: does the unsigned word `w` (u8/u16/u32/u64) sit at
// position `pos` of `t` as a standalone type token? Boundary rules: the
// char before must not be an identifier char (letter / digit / `_`) nor
// `%` (a user-defined type literally named `u8` lowers to `%u8` and must
// survive), and the char after must not be an identifier char (`*`, `,`,
// space, `)`, `}` and end-of-string all terminate a type token).
@ __llty_word_at s t i pos s w → b {
    : i wl ( nurl_str_len w )
    : i tl ( nurl_str_len t )
    ? > + pos wl tl { ^ F } {}
    ? ! ( seq ( nurl_str_slice t pos wl ) w ) { ^ F } {}
    ? > pos 0
    { : i pc ( nurl_str_get t - pos 1 )
        ? | ( __is_ident_char pc ) == pc 37 { ^ F } {} }
    {}
    ? < + pos wl tl
    { ? ( __is_ident_char ( nurl_str_get t + pos wl ) ) { ^ F } {} }
    {}
    ^ T
}

// nurl_llty: lower an internal type to its LLVM spelling. Rewrites every
// standalone u8/u16/u32/u64 token — top-level (`u32`), pointer (`u8*`),
// or embedded in a compound (`{ i1, u8 }`, `{ u16*, i64 }`, closure
// sigs) — to the same-width i-type. All four rewrites are same-length,
// so the result is built with two slices per hit. Types with no `u`
// byte return unchanged (the common case; one memchr-style scan).
@ nurl_llty s t → s {
    // Every path returns an OWNED fresh string (the strdup idiom of
    // nurl_get_last_type): a mixed borrowed-param/owned return would
    // let a caller's owned-arg-temp drop free the very pointer we
    // returned (bit us as garbage `alloca` types in stage2).
    ? ( seq t `u8` ) { ^ # s ( strdup `i8` ) } {}
    ? ( seq t `u16` ) { ^ # s ( strdup `i16` ) } {}
    ? ( seq t `u32` ) { ^ # s ( strdup `i32` ) } {}
    ? ( seq t `u64` ) { ^ # s ( strdup `i64` ) } {}
    : i tl ( nurl_str_len t )
    : ~ i p 0
    ~ < p tl {
        ? & == ( nurl_str_get t p ) 117
        | | ( __llty_word_at t p `u8` ) ( __llty_word_at t p `u16` )
        | ( __llty_word_at t p `u32` ) ( __llty_word_at t p `u64` )
        { : s head ? > p 0 ( nurl_str_slice t 0 p ) ``
            : s tail ( nurl_str_slice t + p 1 - tl + p 1 )
            ^ ( nurl_llty ( nurl_str_cat3 head `i` tail ) ) }
        {}
        = p + p 1
    }
    ^ # s ( strdup t )
}

@ parse_type i lex → s {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_STAR { ^ ( parse_type_ptr lex ) } {}
    ? == tt TT_QUEST { ^ ( parse_type_opt lex ) } {}
    // The lexer fuses adjacent `?` into one `??`, so a nested option
    // written `??T` arrives here as a single token. In type position it
    // unambiguously means option-of-option — the natural type of
    // `vec_get` over a `Vec ?T`.
    ? == tt TT_QUESTQUEST { ^ ( parse_type_optopt lex ) } {}
    ? == tt TT_LBRACK { ^ ( parse_type_slice lex ) } {}
    ? == tt TT_BANG { ^ ( parse_type_res lex ) } {}
    ? == tt TT_LPAREN { ^ ( parse_type_paren lex ) } {}
    ? == tt TT_PIPE { ^ ( parse_type_enum lex ) } {}
    // `%Trait` in type position is a dynamic trait object (docs/spec.md §4.9):
    // a fat pointer `{ data, vtable }` lowered to the named LLVM type
    // `%dyn.<Trait>`. The `%` sigil already means "trait" everywhere; parse_type
    // had no `%` case, so this is collision-free (and the `.` in the lowered
    // name can never clash with a user struct, whose names are plain idents).
    // `%Trait` in type position → dynamic trait object (parse_type_dyn is
    // defined later, alongside the other dyn helpers, so it can reference the
    // trait globals declared below).
    ? == tt TT_PERCENT { ^ ( parse_type_dyn lex ) } {}
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
        // Lint: a type name in type position is a reference — an
        // import supplying only types must count as used.
        ( lint_note_used v )
        ( nurl_lex_advance lex )
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
        ( lint_note_used v )
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
    ? ( seq lty `u64` ) ^ 8
    ? ( seq lty `u32` ) ^ 4
    ? ( seq lty `u16` ) ^ 2
    ? ( seq lty `u8` ) ^ 1
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
        : ~ s params ``
        ~ & != ( nurl_lex_type lex ) TT_RPAREN != ( nurl_lex_type lex ) TT_EOF {
            : s p ( parse_type lex )
            = params ? == 0 ( nurl_str_len params )
            p
            ( nurl_str_cat params ( nurl_str_cat `, ` p ) )
        }
        ( expect lex TT_RPAREN )  // consume ')'
        // Return a closure struct type: { ret (i8*, params...)*, i8* }
        : ~ s fn_sig ( nurl_str_cat ret ` (i8*` )
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
            ( lint_note_used sname )
            ( nurl_lex_advance lex )
            : ~ s mangle_sfx ``
            : ~ b has_tparam_arg F
            // EOF guard: an unterminated type application `( Name a b …` (which
            // can be reached as an enum payload type, e.g. a stray `( foo` with
            // no `)`) otherwise spins here on a no-op `nurl_lex_advance` at EOF.
            // The trailing `expect TT_RPAREN` reports a clean error.
            ~ & != ( nurl_lex_type lex ) TT_RPAREN != ( nurl_lex_type lex ) TT_EOF {
                : i ta_tt ( nurl_lex_type lex )
                // A bare anonymous slice (`[ T`) is the one type shape the
                // monomorphiser cannot mangle as a generic argument: the
                // single-token path below would grab the lone `[` and emit a
                // garbage mangled type that only clang rejects. Reject it here
                // with the documented cure (see spec.md §7.5 / grammar.ebnf
                // generic_arg).
                ? == ta_tt TT_LBRACK
                { ( die lex `a slice type '[ T' cannot be a generic type argument — wrap it in a named struct (e.g. ': Buf [T] { [ T xs }') and instantiate that` ) }
                {}
                // Paren-compound and prefix (`?T` / `??T` / `*T`) args go
                // through parse_type, which yields their LLVM type directly
                // (mangle by LLVM type). A bare base name takes the single-
                // token path and is mangled SIGNEDNESS-AWARE via mangle_src_word
                // so `( Vec u64 )` and `( Vec i )` stay distinct monomorphs.
                ? | | == ta_tt TT_LPAREN == ta_tt TT_QUEST | == ta_tt TT_QUESTQUEST == ta_tt TT_STAR
                { : s ta_lty ( parse_type lex )
                    = mangle_sfx ( nurl_str_cat mangle_sfx
                    ( nurl_str_cat `__` ( mangle_type ta_lty ) ) ) }
                { : s ta ( nurl_lex_val lex )
                    ( lint_note_used ta )
                    ( nurl_lex_advance lex )
                    ? ( is_tparam_like ta ) { = has_tparam_arg T } {}
                    = mangle_sfx ( nurl_str_cat mangle_sfx
                    ( nurl_str_cat `__` ( mangle_src_word ta ) ) ) }
            }
            ( expect lex TT_RPAREN )
            // Unknown-generic check (critic A7): `( Vec i )` with no
            // generic struct template named `Vec` in scope produces a
            // `%Vec__i64` reference that nothing ever defines — LLVM
            // then rejects the unsized type with a cryptic "loading
            // unsized types is not allowed" far from the real cause
            // (usually a missing `$` import). Die here instead, at the
            // use site. Exemptions: abstract instantiations whose args
            // are still tparams (`( Vec T )` inside a generic template
            // — the concrete pass re-enters with real args), and a
            // mangled name some earlier pass already defined.
            ? ! has_tparam_arg
            { ( __die_if_unknown_generic lex sname mangle_sfx ) }
            {}
            ^ ( nurl_str_cat `%` ( nurl_str_cat sname mangle_sfx ) )
        }
        { ( die lex `( in type position must be followed by @ or type name` ) ^ `i64` }
    }
}

// compound_field_type: return LLVM type of field idx in an inline aggregate
// type string `{ f0, f1, ... }`. Depth-aware: nested `{ }` / `( )` in a field
// (an option/slice/result payload, a closure type) don't split the field. This
// indexes opt `{ i1, T }` (0/1), res `{ i1, T, E }` (0/1/2), and slice
// `{ T*, i64 }` (0/1) uniformly. Falls back to i64 for a non-`{` type.
@ compound_field_type s agg_ty i idx → s {
    : i len ( nurl_str_len agg_ty )
    ? | < len 4 != ( nurl_str_get agg_ty 0 ) 123 { ^ `i64` } {}
    : ~ i depth 0
    : ~ i cur 0  // index of the field currently being scanned
    : ~ i fstart 2  // first field begins just after the leading "{ "
    : ~ i i 0
    ~ < i len {
        : i c ( nurl_str_get agg_ty i )
        ? | == c 123 == c 40 { = depth + depth 1 } {}
        ? | == c 125 == c 41
        { = depth - depth 1
            // Closing the outer aggregate: the last field ends at " }".
            ? == depth 0
            { ? == cur idx { ^ ( nurl_str_slice agg_ty fstart - - i 1 fstart ) } {}
                = cur + cur 1 }
            {} }
        {}
        // A top-level comma ends field `cur`; the next begins after ", ".
        ? & == depth 1 == c 44
        { ? == cur idx { ^ ( nurl_str_slice agg_ty fstart - i fstart ) } {}
            = cur + cur 1
            = fstart + i 2 }
        {}
        = i + i 1
    }
    `i64`
}

// agg_field_count: number of fields in an aggregate LLVM type, or -1 when
// unknown (so the caller skips range-checking rather than risk a false
// positive). A named struct `%T` reads its registered `<T>__field_count`; an
// inline aggregate `{ … }` counts the top-level comma separators (depth-aware,
// so nested `{ }` / `( )` don't inflate the count). Used by gen_member to
// reject an out-of-range `. agg INT` before it emits an invalid extractvalue.
@ agg_field_count i syms s ot → i {
    : i n ( nurl_str_len ot )
    ? == 0 n { ^ -1 } {}
    ? == ( nurl_str_get ot 0 ) 37
    { : s nm ( nurl_str_slice ot 1 - n 1 )
        : s fc ( nurl_sym_get syms ( nurl_str_cat nm `__field_count` ) )
        ? != 0 ( nurl_str_len fc ) { ^ ( nurl_str_to_int fc ) } { ^ -1 } }
    {}
    ? == ( nurl_str_get ot 0 ) 123
    { : ~ i depth 0
        : ~ i count 1
        : ~ i i 0
        ~ < i n {
            : i c ( nurl_str_get ot i )
            ? | == c 123 == c 40 { = depth + depth 1 } {}
            ? | == c 125 == c 41 { = depth - depth 1 } {}
            ? & == depth 1 == c 44 { = count + count 1 } {}
            = i + i 1
        }
        ^ count }
    {}
    -1
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

// ?? T  →  { i1, { i1, T } }   (option-of-option)
// `??` is one fused token; the outer wrapper's payload is the inner
// option type. Record the side-channels for the OUTER option so a
// binding's `T inner →` arm reconstructs `inner` at the inner-option
// type `{ i1, T }`.
@ parse_type_optopt i lex → s {
    ( nurl_lex_advance lex )  // consume '??'
    : s inner_tok ( nurl_lex_val lex )
    : s inner ( parse_type lex )
    : s inner_opt ( nurl_str_cat `{ i1, ` ( nurl_str_cat inner ` }` ) )
    ( nurl_sym_def g_res_type_syms `__last_opt_nurl_t__` inner_tok )
    ( nurl_sym_def g_res_type_syms `__last_opt_t_llvm__` inner_opt )
    ^ ( nurl_str_cat `{ i1, ` ( nurl_str_cat inner_opt ` }` ) )
}

// Convert a NURL-source type spelling (e.g. "?String", "??i", "*u",
// "Vec__u", "String") to its LLVM type. Handles the `?` / `??` / `*`
// prefix constructors recursively and delegates base names to
// `llvm_type`. Used by generic instantiation to mangle compound
// (option / pointer) type arguments.
@ nurl_src_to_llvm s src → s {
    : i n ( nurl_str_len src )
    ? == n 0 { ^ `i8*` } {}
    : i c0 ( nurl_str_get src 0 )
    ? & & == c0 63 >= n 2 == ( nurl_str_get src 1 ) 63
    { ^ ( nurl_str_cat `{ i1, ` ( nurl_str_cat ( nurl_src_to_llvm ( nurl_str_slice src 2 - n 2 ) ) ` }` ) ) }
    {}
    ? == c0 63
    { ^ ( nurl_str_cat `{ i1, ` ( nurl_str_cat ( nurl_src_to_llvm ( nurl_str_slice src 1 - n 1 ) ) ` }` ) ) }
    {}
    ? == c0 42
    { : s inner ( nurl_src_to_llvm ( nurl_str_slice src 1 - n 1 ) )
        ? ( seq inner `void` ) { ^ `i8*` } { ^ ( nurl_str_cat inner `*` ) } }
    {}
    ^ ( llvm_type src )
}

// Capture the NURL-source spelling of a type argument at the current
// lexer position, consuming its tokens. Handles the prefix constructors
// `?` / `??` (the lexer fuses adjacent `?`) / `*` so a compound option /
// pointer type argument like `?String` is kept as one substitutable
// word — `nurl_lex_val` alone would grab only the leading `?`. Paren-
// compound args are handled separately by the caller.
@ capture_type_arg_src i lex → s {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_QUEST
    { ( nurl_lex_advance lex ) ^ ( nurl_str_cat `?` ( capture_type_arg_src lex ) ) }
    {}
    ? == tt TT_QUESTQUEST
    { ( nurl_lex_advance lex ) ^ ( nurl_str_cat `??` ( capture_type_arg_src lex ) ) }
    {}
    ? == tt TT_STAR
    { ( nurl_lex_advance lex ) ^ ( nurl_str_cat `*` ( capture_type_arg_src lex ) ) }
    {}
    : s v ( nurl_lex_val lex )
    ( nurl_lex_advance lex )
    ^ v
}

// [ T  →  { T*, i64 }
@ parse_type_slice i lex → s {
    ( nurl_lex_advance lex )
    : s inner ( parse_type lex )
    ( nurl_str_cat `{ ` ( nurl_str_cat inner `*, i64 }` ) )
}

// ! T E  →  { i1, T, E }
// Ok payload lives by value in field 1 (type T), Err payload by value in
// field 2 (type E); the i1 tag in field 0 selects the live slot (1 = Ok).
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
    // Result is `{ i1, T, E }` — Ok payload by value in field 1, Err payload
    // by value in field 2 (the tag in field 0 selects which slot is live).
    // A `void` payload cannot sit in an LLVM struct, so a `!v E` Ok slot
    // lowers to a 1-byte `i1` placeholder that the Ok arm never reads (no
    // `!T v` form occurs in-tree, but the Err slot is guarded symmetrically).
    : s f1 ? ( seq lt `void` ) `i1` lt
    : s f2 ? ( seq le `void` ) `i1` le
    ^ ( nurl_str_cat `{ i1, ` ( nurl_str_cat3 f1 `, ` ( nurl_str_cat f2 ` }` ) ) )
}

// ── Emit helpers ──────────────────────────────────────────────────

@ emit s line → v { ( nurl_print line ) ( nurl_print `\n` ) }

@ emiti s line → v { ( nurl_print `  ` ) ( nurl_print line ) ( nurl_print `\n` ) }

// DWARF-aware emit helpers live further down (after g_dbg_* globals
// have been declared) — see `emit_dbg_eol` / `emit_call` /
// `emit_call_term` / `emit_inst` below.

// ── String literal encoding ───────────────────────────────────────

: ~ i g_str_idx 0
: ~ i g_str_syms 0  // sym handle for string-literal metadata (never pushed/popped)
: ~ i g_did_ret 0  // set to 1 by gen_ret; checked/reset by gen_cond
// Cascade guard: 1 while parsing a VALUE OPERAND (a binary/unary/cast/
// member operand, a call argument, a `?`/`??` condition/scrutinee, or a
// return value). `^` (return) is control flow and is meaningless in those
// positions — encountering it means a preceding fixed-arity prefix
// operator was short an argument and silently consumed the `^`, so
// gen_ret dies with a cascade diagnostic instead of emitting a `ret`
// mid-expression (dead code after the terminator — a silent miscompile).
// Default 0 (statement / tail position, where `^` is legal); set to 1 by
// gen_operand around operand parses, and reset to 0 by the control-flow
// handlers for their arm/body sub-parses (which ARE legal `^` positions).
: ~ i g_ret_forbidden 0
// Non-zero while parsing a `??` match-arm body. The XOR-confusion warning
// in gen_ret keys off "a non-terminator token follows `^ X` on the same
// line", but in an unbraced arm body that token is the NEXT ARM's pattern
// (`T x → ^ x  F _ → …`), not a stray XOR operand — so the warning is
// suppressed inside arm bodies. Save/restore (nested matches).
: ~ i g_in_match_arm 0
: ~ i g_defer_count 0  // number of active defers in the current function
: ~ i g_generic_syms 0  // sym handle for stored generic function templates (Group E)
: ~ i g_generic_struct_syms 0  // generic struct templates (Group E-structs).
//   <sname>__stparams → space-separated type-var names (e.g. "T" or "K V")
//   <sname>__sbody    → raw body source incl. outer "{ ... }"
: ~ i g_struct_inst_syms 0  // dedupe marker — <mangled>__done → "1" once emitted
: ~ i g_impl_ret_syms 0  // Group F: method##llvm_type → ret_type string
: ~ i g_impl_name_syms 0  // Group F: method##llvm_type → mangle_suffix string
: ~ i g_impl_trait_syms 0  // coherence: method##llvm_type → owning trait name
: ~ i g_impl_pos_syms 0  // coherence: method##llvm_type → "file:line" of the
//   first registration. A `$`-imported impl is scanned once per importer, so
//   the SAME (method, type) is registered from the SAME source location more
//   than once — those re-scans are idempotent (allowed). A registration from a
//   DIFFERENT location is a genuine duplicate impl, or two traits sharing a
//   method name for one type (incl. alias types like i / i64 that share an
//   LLVM type) — reported as a clean diagnostic, not an LLVM redefinition.
: ~ i g_trait_syms 0  // Trait default implementations.
//   <Trait>__tparam           → trait's generic type-var name (e.g. "T")
//   <Trait>__defaults         → space-separated method names with defaults
//   <Trait>__<method>__src    → raw source "params → ret { body }"
//   <Trait>__istrait          → "1" once the trait header is seen (a definite
//                               existence marker — __tparam is "" for the
//                               common untyped trait, indistinguishable from
//                               absent, so supertrait checks key on this)
//   <Trait>__supers           → space-separated supertrait names (% Sub : A B)
//   <Trait>__assoc            → space-separated associated-type names (type Item)
//   <Trait>__methods          → method names in declaration order (dyn seam)
//   <Trait>__<method>__sig    → that method's "params → ret" signature (dyn seam)
// Dynamic trait objects (`%Trait`, docs/spec.md §4.9). Space-separated set of
// trait names that appear as a `%Trait` object type or in a `( dyn Trait v )`
// construction anywhere in the program (collected by scan_dyn_types, a body-
// aware pre-pass). Each becomes an `%dyn.<T> = type { i8*, i8* }` fat pointer
// (data ptr + vtable ptr) plus a synthesized Drop impl, emitted at module
// scope before parse_program. Over-collection is harmless (unused type def).
: ~ s g_dyn_needed ``
// Scratch accumulators for dyn_flat_methods (a NURL fn returns one value, so
// the recursive supertrait walk threads its result through these globals).
: ~ s g_dyn_flat_out ``
: ~ s g_dyn_flat_seen ``
: ~ s g_super_obligations ``  // one "<Sub> <impl_llvm> <nurl_type> <file:line>\n"
//   record per impl block, verified after scan_fn_sigs once every impl across
//   the program (incl. imports) is registered: a supertrait of an implemented
//   trait must itself be implemented for that same type (T: Sub ⇒ T: Super).
// Thread-safety: name of a non-Send capture (an Rc) of the most recently built
// closure, or "" if it had none. A real global (not a `syms` side-channel) so
// it survives across the differing symbol tables of closure-build vs the
// thread_spawn call site. Cleared at each closure build; the enclosing `:`
// binding copies it to `<name>__closure_nonsend`; the thread_spawn call site
// reads it (inline closure) or that per-binding key (named closure).
: ~ s g_last_closure_nonsend ``
: ~ i g_closure_defs 0  // Deferred closure function definitions
: ~ i g_closure_types 0  // Deferred closure type definitions
: ~ i g_type_count 0  // Count of closure types stored
: ~ i g_func_count 0  // Count of closure functions stored
: ~ i g_closure_emit_base 0  // Next func index to emit (watermark)
: ~ i g_type_emit_base 0  // Next type index to emit

// ── Borrow-checker state ─────────────────────────────────────────
// g_borrowck is 1 (ON) by default; `--no-borrowck` turns it back off.
// The borrow checker is a diagnostic-only analysis pass: it never
// emits IR, so a borrow-clean program produces byte-identical IR
// whether the flag is on or off (the bootstrap fixed point is
// unaffected). All borrowck_* state below is untouched when the flag
// is 0.
: ~ i g_borrowck 1  // 0 when --no-borrowck passed on the CLI
// g_ffi_host_imports is 1 when `--ffi-host-imports` is passed: external
// `&`-FFI libraries are then satisfied by the RUN-TIME host (wasm imports
// resolved by the embedder) rather than by a native link line, so the
// build-time `stdlib/runtime.<lib>` sentinel gate is skipped. Set by the
// wasm build path (nurlapi) — a wasm module's undefined FFI symbols become
// imports the host runtime (e.g. packages/wasmtime) provides.
: ~ i g_ffi_host_imports 0
// `--strict-borrowck` (off by default) enables two additional checks:
// (1) aliased mutation through `. obj field` arguments at the same
// call site — a generalisation of the bare-identifier-only check, and
// (2) `# *T` raw-pointer escape from owned bindings whose pointer may
// outlive the binding's drop. Both are diagnostic-only and emit
// `error:` like the rest of the borrowck. Disabled by default because
// the extension has a meaningful false-positive rate against existing
// stdlib code.
: ~ i g_strict_borrowck 0  // 1 when --strict-borrowck passed on the CLI
: ~ i g_bck 0  // sym handle for the borrow checker's per-function
//  data (statement list etc.); allocated in main()
//  only when --borrowck is set
: ~ i g_bck_depth 0  // block-nesting depth during the statement walk
: ~ i g_bck_closure_depth 0  // >0 while parsing a closure body — the bck
//  capture hooks no-op so closure statements do not
//  inline into the enclosing function's list (so
//  closure scopes stay segregated)
: ~ i g_bck_errors 0  // count of borrow errors emitted so far. Errors
//  do not abort on the spot — every violation is
//  surfaced in one run, the same as a C compiler;
//  the diagnostic helpers bump this counter and
//  main() exits non-zero if it
//  is > 0 once parsing finishes. --no-borrowck and
//  borrow-clean programs both leave this at 0 so
//  the bootstrap fixed point is unaffected.

// Per-function inout-parameter map.
// `g_fn_inout[fname]` is the space-separated list of 0-based indices
// of `inout` parameters, recorded by gen_fn_decl_concrete as each
// function is compiled. gen_call consults it to pass those arguments
// by address. Allocated in main(). It is a *codegen-order* table:
// an `inout` function must be defined before it is called (a forward
// call would pass the argument by value and LLVM would reject the
// type mismatch — loud, never silent).
: ~ i g_fn_inout 0

// Per-function sink-parameter map.
// `g_fn_sink[fname]` is the space-separated list of 0-based indices
// of `sink` parameters. A `sink` parameter consumes (moves) its
// argument: codegen is an ordinary by-value pass (no IR change), and
// gen_call records the argument binding as borrow-checker-moved so
// the caller cannot use it afterwards. Unlike g_fn_inout, a forward
// call needs no guard — it merely misses the move diagnostic, it is
// never miscompiled. Allocated in main().
: ~ i g_fn_sink 0

// Per-function escaping-parameter map.
// `g_fn_escapes[fname]` is the space-separated list of 0-based indices
// of parameters whose value the body *retains past the call* — stored
// into a heap container or detached onto a thread (directly, or
// transitively through another function's escaping parameter). Inferred
// in codegen order like g_fn_sink (a forward call merely misses the
// diagnostic, never miscompiles). gen_call consults it to flag a stack
// reference handed to such a parameter — the interprocedural escape
// check (docs/MEMORY.md §2.7). Allocated in main().
: ~ i g_fn_escapes 0

// Per-function *invoke-only* parameter map (closure-env reclamation,
// docs/MEMORY.md §7.4). `g_fn_invoke_only[fname]` is the space-separated
// list of 0-based parameter indices that the body uses ONLY as the
// callee of a call (`( f x )`) — never loaded as a value (passed as an
// argument, returned, stored, decomposed, or captured). Such a parameter
// is a pure *borrow*: the closure it names cannot outlive the call, so a
// caller passing an inline closure literal there may free that literal's
// heap env after the call. This is the POSITIVE dual of g_fn_escapes —
// it must never over-claim, so any value-load of a parameter drops it
// from the set (a forward/unknown callee yields the empty set, i.e. no
// free). Computed deterministically (never gated on the borrow checker)
// so generated IR is identical with or without it. Allocated in main().
: ~ i g_fn_invoke_only 0

// Deferred interprocedural-escape checks (docs/MEMORY.md §3 forward /
// generic boundary). A stack reference passed to a *user* function
// whose escape summary is not yet known at the call site — a forward
// call, or a generic not yet instantiated — cannot be resolved inline.
// gen_call parks such a check here as a space-separated 5-tuple
// `call_name fname arg_idx line file`; resolve_pending_escapes() replays
// each one against the now-complete g_fn_escapes after the whole module
// (including the generic instantiation flush) has compiled. Only stack-
// reference arguments are ever parked, so the list stays tiny.
// Allocated in main(); the list lives under key `l`.
: ~ i g_pending_escape 0

// Per-function returned-parameter map.
// `g_fn_ret_param[fname]` is the space-separated list of 0-based
// indices of parameters the body may RETURN directly (`^ p` /
// implicit-final `p`). Inferred in codegen order. gen_call uses it to
// propagate a stack reference OUT through the call result: the result
// of `( id ref )` carries `ref`'s referent depth, so the existing
// §2.3 sinks (`^`-return, vec_push, shallower `=`) then catch a
// returned borrow that dangles. The dual of g_fn_escapes (which
// propagates a reference INTO a callee). docs/MEMORY.md §2.8.
// Allocated in main().
: ~ i g_fn_ret_param 0

// ── DWARF debug-info state ───────────────────────────────────────
// All zero/empty when --g is OFF; emit helpers then produce IR that
// is byte-identical to a pre-DWARF build. Toggled in main().
: ~ i g_dbg_enabled 0  // 1 when --g passed on the CLI
: ~ i g_dbg_next_id 100  // metadata-id allocator; starts above any
//  module-flag id we might add later
: ~ i g_dbg_blob_syms 0  // sym handle holding queued !N = !DI… lines;
//  flushed at end-of-module by dbg_flush
: ~ i g_dbg_file_id 0  // !DIFile id (allocated once at startup)
: ~ i g_dbg_cu_id 0  // !DICompileUnit id
: ~ i g_dbg_current_subprogram 0  // current function's !DISubprogram id
//  (0 outside any function)
: ~ i g_dbg_current_loc 0  // current !DILocation id (0 = no location;
//  emit_dbg_eol then omits `, !dbg !N`)
: ~ i g_dbg_subroutine_ty 0  // shared !DISubroutineType id; allocated by
//  dbg_init and reused for every fn. Phase 6
//  will replace with per-fn signature types.
: ~ i g_dbg_placeholder_ty 0  // shared !DIBasicType id (i64-signed) used as
//  the type for every local until Phase 6
//  lays down per-LLVM-type DIBasicType
//  entries indexed by `vt`.
: ~ i g_dbg_override_line 0  // Phase 7: when non-zero, gen_fn_decl_concrete
//  uses this instead of `nurl_lex_line` for
//  the !DISubprogram source line. Set by
//  emit_one_instantiation so per-mono
//  subprograms point at the original generic
//  decl line, not synthetic `<generic>:1`.
: ~ i g_dbg_file_syms 0  // Phase 8 (critic A8): path → !DIFile id cache so
//  every source file gets its own !DIFile and a
//  subprogram debug-attributes to the file that
//  DEFINES it (imports, stdlib generics), not the
//  top-level compile file.
: ~ s g_dbg_override_file ``  // Phase 8: when non-empty, the template's
//  defining path for the mono being emitted
//  (the mono's lexer filename is the synthetic
//  `<generic …>`). Set/restored by
//  emit_one_instantiation beside the line
//  override.
: ~ i g_dbg_current_file_id 0  // !DIFile id of the current subprogram's
//  defining file (0 outside any function);
//  dbg_declare_local points DILocalVariable.file
//  here so locals land in the same file as
//  their subprogram.

// Space-separated list of the concrete type-arguments substituted for a
// generic function's type parameters in the instantiation currently being
// emitted (set + restored by emit_one_instantiation). Empty outside any
// instantiation. A struct pointer whose element type is one of these names
// arose, in the generic SOURCE, from an opaque type variable (`A`) — which
// has no source-accessible fields. So `. ptr name` / `= . ptr name v` on
// such a pointer is ALWAYS array indexing, never field access: the field-
// index lookup in gen_member / gen_field_store is suppressed for these
// types. This is what makes `( vec_get [T] v idx )` index element `idx`
// even when `T` happens to have a field literally named `idx` (textual
// monomorphisation otherwise loses the "this type was a tparam" signal).
: ~ s g_mono_tparam_tys ``
: ~ i g_dbg_type_syms 0  // Phase 6 type-id cache: LLVM type string
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

// ── DWARF helpers ────────────────────────────────────────────────
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
    // Per-file !DIFile cache, pre-seeded with the top-level file so a
    // single-file program emits exactly the metadata it always did.
    = g_dbg_file_syms ( nurl_sym_new )
    ( nurl_sym_def g_dbg_file_syms path ( nurl_str_int g_dbg_file_id ) )
}

// Phase 8 (critic A8): !DIFile id for `path`, buffering a new !DIFile
// on first use. Empty/synthetic paths (`<generic …>`, `<repl>`, …)
// fall back to the top-level file id.
@ dbg_file_id_for s path → i {
    ? == 0 ( nurl_str_len path ) { ^ g_dbg_file_id } {}
    ? == ( nurl_str_get path 0 ) 60 { ^ g_dbg_file_id } {}
    : s got ( nurl_sym_get g_dbg_file_syms path )
    ? != 0 ( nurl_str_len got ) { ^ ( nurl_str_to_int got ) } {}
    : i fid ( dbg_alloc_id )
    ( dbg_buffer_meta fid
    ( nurl_str_cat3 `!DIFile(filename: "` path `", directory: ".")` ) )
    ( nurl_sym_def g_dbg_file_syms path ( nurl_str_int fid ) )
    ^ fid
}

// The !DIFile id the CURRENT function should debug-attribute to: the
// generic-template override when a mono is being emitted (its lexer
// filename is synthetic), otherwise the emitting lexer's filename —
// which is the IMPORTED file's path while an import is being walked,
// closing the "stdlib fn points at the top file" gap.
@ dbg_file_for_lex i lex → i {
    ? != 0 ( nurl_str_len g_dbg_override_file )
    { ^ ( dbg_file_id_for g_dbg_override_file ) } {}
    ^ ( dbg_file_id_for ( nurl_lex_filename lex ) )
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
    ? ( seq vt `i1` ) { ^ 8 } {}
    ? ( seq vt `i8` ) { ^ 8 } {}
    ? ( seq vt `i16` ) { ^ 16 } {}
    ? ( seq vt `i32` ) { ^ 32 } {}
    ? ( seq vt `i64` ) { ^ 64 } {}
    ? ( seq vt `u8` ) { ^ 8 } {}
    ? ( seq vt `u16` ) { ^ 16 } {}
    ? ( seq vt `u32` ) { ^ 32 } {}
    ? ( seq vt `u64` ) { ^ 64 } {}
    ? ( seq vt `float` ) { ^ 32 } {}
    ? ( seq vt `double` ) { ^ 64 } {}
    ^ 64
}

@ dbg_align_bits s vt → i {
    ? ( seq vt `i1` ) { ^ 8 } {}
    ? ( seq vt `i8` ) { ^ 8 } {}
    ? ( seq vt `i16` ) { ^ 16 } {}
    ? ( seq vt `i32` ) { ^ 32 } {}
    ? ( seq vt `i64` ) { ^ 64 } {}
    ? ( seq vt `u8` ) { ^ 8 } {}
    ? ( seq vt `u16` ) { ^ 16 } {}
    ? ( seq vt `u32` ) { ^ 32 } {}
    ? ( seq vt `u64` ) { ^ 64 } {}
    ? ( seq vt `float` ) { ^ 32 } {}
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
    : ~ i id 0
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
        ( dbg_buffer_meta id `!DIBasicType(name: "i8", size: 8, encoding: DW_ATE_signed)` ) }
    // The unsigned internal scalars (A1) render faithfully — gdb shows
    // `u` / `u16` / `u32` / `u64` with DW_ATE_unsigned.
    ? ( seq vt `u8` )
    { = id ( dbg_alloc_id )
        ( dbg_buffer_meta id `!DIBasicType(name: "u", size: 8, encoding: DW_ATE_unsigned)` ) }
    ? ( seq vt `u16` )
    { = id ( dbg_alloc_id )
        ( dbg_buffer_meta id `!DIBasicType(name: "u16", size: 16, encoding: DW_ATE_unsigned)` ) }
    ? ( seq vt `u32` )
    { = id ( dbg_alloc_id )
        ( dbg_buffer_meta id `!DIBasicType(name: "u32", size: 32, encoding: DW_ATE_unsigned)` ) }
    ? ( seq vt `u64` )
    { = id ( dbg_alloc_id )
        ( dbg_buffer_meta id `!DIBasicType(name: "u64", size: 64, encoding: DW_ATE_unsigned)` ) }
    ? ( seq vt `i1` )
    { = id ( dbg_alloc_id )
        ( dbg_buffer_meta id `!DIBasicType(name: "b", size: 8, encoding: DW_ATE_boolean)` ) }
    ? ( seq vt `double` )
    { = id ( dbg_alloc_id )
        ( dbg_buffer_meta id `!DIBasicType(name: "f", size: 64, encoding: DW_ATE_float)` ) }
    ? ( seq vt `float` )
    { = id ( dbg_alloc_id )
        ( dbg_buffer_meta id `!DIBasicType(name: "f32", size: 32, encoding: DW_ATE_float)` ) }
    ? ( seq ( nurl_llty vt ) `i8*` )
    { = id ( dbg_alloc_id )
        : i u8_id ( dbg_type_id_for `i8` syms )
        ( dbg_buffer_meta id
        ( nurl_str_cat3
        `!DIDerivedType(tag: DW_TAG_pointer_type, baseType: !`
        ( nurl_str_int u8_id )
        `, size: 64)` ) ) }
    // Pointer to a named struct (`%Name*`, `%Name**`, …): emit a
    // DW_TAG_pointer_type wrapping the pointee's DI type so gdb can
    // `print *p` and `p->field`. Recursion peels one `*` per level.
    ? & == id 0 & == 37 ( nurl_str_get vt 0 ) == 42 ( nurl_str_get vt - ( nurl_str_len vt ) 1 )
    { : s pointee ( nurl_str_slice vt 0 - ( nurl_str_len vt ) 1 )
        : i base_id ( dbg_type_id_for pointee syms )
        = id ( dbg_alloc_id )
        ( dbg_buffer_meta id
        ( nurl_str_cat3
        `!DIDerivedType(tag: DW_TAG_pointer_type, baseType: !`
        ( nurl_str_int base_id ) `, size: 64)` ) ) }
    {}
    // Named structs (handle: '%' prefix). Try the composite-type path
    // — if syms knows the struct, emit !DICompositeType + per-field
    // !DIDerivedType DW_TAG_member entries. Otherwise fall through.
    //
    // The explicit `{}` else is load-bearing: a chain of single-branch
    // `?` statements nests each following `?` as the previous one's
    // ELSE, so without it the placeholder fallback below was the
    // composite-?'s else — skipped exactly when the composite branch
    // RAN and returned 0 (unknown struct), leaking `type: !0` into the
    // metadata and failing the whole --g build at the clang stage.
    ? & == id 0 == 37 ( nurl_str_get vt 0 )
    { = id ( dbg_emit_composite vt syms ) }
    {}
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
        : ~ s fname ( nurl_sym_get syms
        ( nurl_str_cat3 base `__idx_` ( nurl_str_cat ( nurl_str_int fidx ) `__name` ) ) )
        : ~ s ftype ( nurl_sym_get syms
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
//   `file` — !DIFile id of the DEFINING source file (dbg_file_for_lex);
//            0 falls back to the top-level file.
@ dbg_emit_subprogram s lname i line i file → i {
    : i sp_id ( dbg_alloc_id )
    : s ls ( nurl_str_int line )
    : s fid ( nurl_str_int ? != file 0 file g_dbg_file_id )
    : s cu ( nurl_str_int g_dbg_cu_id )
    : s part1 ( nurl_str_cat3 `distinct !DISubprogram(name: "` lname `"` )
    : s part2 ( nurl_str_cat3 `, scope: !` fid `, file: !` )
    : s part3 ( nurl_str_cat3 fid `, line: ` ls )
    : s part4 ( nurl_str_cat3 `, scopeLine: ` ls `, unit: !` )
    : s ty ( nurl_str_int g_dbg_subroutine_ty )
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
        : s fi ( nurl_str_int ? != g_dbg_current_file_id 0 g_dbg_current_file_id g_dbg_file_id )
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
        ( nurl_print ( nurl_llty vt ) ) ( nurl_print `* ` ) ( nurl_print ptr )
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
: ~ i g_auto_drop_strings 1

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
: ~ i g_pending_pub 0
: ~ i g_vis_syms 0

// Unused-symbol lint (opt-in via `--lint`). Default OFF so ordinary
// builds — and the compiler's own bootstrap, which never passes
// `--lint` — emit byte-identical IR and stay at their fixed point.
// Every lint hook below is guarded on `g_lint`, writes only to the
// sym handles here + stderr, and never touches codegen state, so IR
// output is unaffected when the flag is off.
//
//   g_lint_syms  — keys `top` (top-level source path), `fns`
//                  (compile-global "name\tline\tcol\tfile\n" rows for
//                  every @-decl in the top file) and `binds` (the
//                  current function's "name\tline\tcol\n" rows).
//   g_lint_used  — compile-global set: every name passed to gen_call
//                  or read in gen_ident. A private @-fn whose name is
//                  absent here was never referenced.
//   g_lint_reads — per-function read set, keyed "<gen> <name>". The
//                  generation (g_lint_gen) bumps each function so a
//                  read in one function never satisfies a same-named
//                  binding in another — no reset / handle churn needed.
//                  Reads are recorded UNCONDITIONALLY (unlike the
//                  borrow checker, which suppresses inside closures),
//                  so a binding used only by a captured closure is
//                  correctly seen as used.
: ~ i g_lint 0
: ~ i g_lint_syms 0
: ~ i g_lint_used 0
: ~ i g_lint_reads 0
: ~ i g_lint_gen 0
// 1 only during the main parse_program pass. Cleared before
// flush_deferred_instantiations so synthetic generic monomorphisations
// (e.g. vec_with_cap__i64), which are emitted after the parse and carry
// the top file's current-src-file, are NOT recorded as the user's own
// unused functions / bindings. Reference + use capture stays on
// throughout so the used-set remains complete.
: ~ i g_lint_recording 0

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
    ( lint_note_def fname )
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
    ( lint_note_def sname )
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
    ( lint_note_def cname )
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

// ── Unused-symbol lint helpers (all inert unless `--lint`) ─────────

// Set up lint state. Called once from main when `--lint` is passed,
// after the top-level source path is known.
@ lint_init s top → v {
    = g_lint_syms ( nurl_sym_new )
    = g_lint_used ( nurl_sym_new )
    = g_lint_reads ( nurl_sym_new )
    ( nurl_sym_def g_lint_syms `top` top )
    ( nurl_sym_def g_lint_syms `fns` `` )
    ( nurl_sym_def g_lint_syms `binds` `` )
}

// True when the file being parsed right now is the user's top-level
// file (not a transitively `$`-imported one): unused-symbol lints
// only fire for the file the user is actually editing, so a stdlib
// helper the program happens not to use is never flagged.
@ lint_in_top_file → b {
    ? == g_lint 0 { ^ F } {}
    ^ ( seq ( vis_current_src_file ) ( nurl_sym_get g_lint_syms `top` ) )
}

// Emit one `<file>:<line>:<col>: warning: <msg>` line in the exact
// shape nurlc's `warn` uses, so the LSP's diagnostic parser surfaces
// it as a Warning.
@ lint_warn s file i line i col s msg → v {
    ( nurl_eprintln ( nurl_str_cat
    ( nurl_str_cat3 file `:` ( nurl_str_int line ) )
    ( nurl_str_cat4 `:` ( nurl_str_int col ) `: warning: ` msg ) ) )
}

// Record that `name` was referenced (called via gen_call, read via
// gen_ident, or named as a type via parse_type) anywhere in the
// program. Drives the unused-function check (global key) and the
// unused-import check (file-scoped `<file> <name>` key: an import is
// justified only by references in the importing file itself, not by
// uses from elsewhere in the unit).
@ lint_note_used s name → v {
    ? != g_lint 0
    { ( nurl_sym_def g_lint_used name `1` )
        // During the instantiation flush, attribute uses to the
        // generic template's defining file (g_lint_syms `use_file`,
        // set by emit_one_instantiation) — vis_current_src_file has
        // already unwound to the top file by then.
        : s uf ( nurl_sym_get g_lint_syms `use_file` )
        : s sf ? != 0 ( nurl_str_len uf ) uf ( vis_current_src_file )
        ( nurl_sym_def g_lint_used ( nurl_str_cat3 sf ` ` name ) `1` ) }
    {}
}

// Record one top-level decl `name` as belonging to the file being
// parsed right now. Builds the per-file `defs:<file>` roster the
// unused-import lint reads. Called from vis_record_fn / _type /
// _const (which see every @-fn, struct, enum, and const in every
// file) and from gen_ffi_decl for `&` externs. Deduped because the
// scan and parse passes both register the same decls.
// Explicit-file variant: the generic-struct template scan walks `$`
// imports recursively WITHOUT updating vis_current_src_file, so the
// defining file must come from the active lexer's filename there.
@ lint_note_def_at s name s sf → v {
    ? != g_lint 0
    { : s seenkey ( nurl_str_cat4 `defseen:` sf `\t` name )
        ? != 0 ( nurl_str_len ( nurl_sym_get g_lint_syms seenkey ) ) {}
        { ( nurl_sym_def g_lint_syms seenkey `1` )
            : s key ( nurl_str_cat `defs:` sf )
            : s cur ( nurl_sym_get g_lint_syms key )
            ( nurl_sym_def g_lint_syms key ( nurl_str_cat3 cur name `\t` ) ) }
    }
    {}
}

// Gated on g_lint_recording: the instantiation flush re-enters
// gen_fn_decl for synthetic monomorphisations (`vec_push__i64` …)
// with vis_current_src_file unwound to the TOP file — without the
// gate those mangled names land in the top file's def roster and a
// pure-aggregator top file stops looking like one. (The _at variant
// above stays ungated: the generic-struct pre-scan runs before
// recording starts and carries the true file in its lexer.)
@ lint_note_def s name → v {
    ? & != g_lint 0 != g_lint_recording 0
    { : s sf ( vis_current_src_file )
        : s seenkey ( nurl_str_cat4 `defseen:` sf `\t` name )
        ? != 0 ( nurl_str_len ( nurl_sym_get g_lint_syms seenkey ) ) {}
        { ( nurl_sym_def g_lint_syms seenkey `1` )
            : s key ( nurl_str_cat `defs:` sf )
            : s cur ( nurl_sym_get g_lint_syms key )
            ( nurl_sym_def g_lint_syms key ( nurl_str_cat3 cur name `\t` ) ) }
    }
    {}
}

// Record a top-file `$` import directive (path + position of the `$`
// token) for the unused-import report. Imports inside transitively
// imported files are not recorded — the lint only judges the file the
// user is editing, same as every other unused-symbol lint here.
// Note a type-arg source word (`Header`, `?u`, `*T`, …) as a type
// reference: strip the `?` / `*` / `!` prefix sigils, then record the
// root name. Builtins (`i`, `u8`, …) record harmlessly — they are in
// no file's def roster, so the import check never sees them.
@ lint_note_used_type_word s w → v {
    ? == g_lint 0 { ^ v } {}
    : i n ( nurl_str_len w )
    : ~ i k 0
    ~ & < k n | | == ( nurl_str_get w k ) 63 == ( nurl_str_get w k ) 42 == ( nurl_str_get w k ) 33
    { = k + k 1 }
    ? < k n { ( lint_note_used ( nurl_str_slice w k - n k ) ) } {}
}

// Explicit-file variant of lint_note_used (same reasons as
// lint_note_def_at — callers whose vis_current_src_file is stale).
@ lint_note_used_at s name s sf → v {
    ? != g_lint 0
    { ( nurl_sym_def g_lint_used name `1` )
        ( nurl_sym_def g_lint_used ( nurl_str_cat3 sf ` ` name ) `1` ) }
    {}
}

// Conservatively mark every identifier token in a stored generic
// template source as referenced by `file`. Template bodies are parsed
// only at instantiation — possibly NEVER when linting a library file
// standalone — yet `( Pair K V )` inside `map_iter [K V]`'s body is a
// real reference in hashmap.nu. Lexer-based, so strings and comments
// are skipped; over-marking (locals, tparams) is harmless — unknown
// names are in no def roster.
@ lint_note_template_src s src s file → v {
    ? == g_lint 0 { ^ v } {}
    : i lx ( nurl_lex_new src `<lint-template>` )
    ~ != ( nurl_lex_type lx ) TT_EOF {
        ? ( is_ident_tok ( nurl_lex_type lx ) )
        { ( lint_note_used_at ( nurl_lex_val lx ) file ) }
        {}
        ( nurl_lex_advance lx )
    }
}

@ lint_note_import s path i line i col → v {
    ? & & != g_lint 0 != g_lint_recording 0 ( lint_in_top_file )
    { : s row ( nurl_str_cat
        ( nurl_str_cat3 path `\t` ( nurl_str_int line ) )
        ( nurl_str_cat3 `\t` ( nurl_str_int col ) `\n` ) )
        : s cur ( nurl_sym_get g_lint_syms `imports` )
        ( nurl_sym_def g_lint_syms `imports` ( nurl_str_cat cur row ) ) }
    {}
}

// Record an identifier read in the current function. Recorded for
// every file (cheap) but only queried for top-level-file bindings.
@ lint_note_read s name → v {
    ? != g_lint 0
    { ( nurl_sym_def g_lint_reads
        ( nurl_str_cat3 ( nurl_str_int g_lint_gen ) ` ` name ) `1` ) }
    {}
}

// Begin a fresh per-function lint scope: bump the read generation and
// clear the binding roster. Called at every function-body start.
@ lint_fn_begin → v {
    ? != g_lint 0
    { = g_lint_gen + g_lint_gen 1
        ( nurl_sym_def g_lint_syms `binds` `` ) }
    {}
}

// Record a `:` binding's name + source position for the unused-binding
// check. Any name beginning with `_` is the conventional "intentionally
// unused" throwaway (`_`, `_ok`, `_unused`, …) and is never flagged.
@ lint_note_bind i lex s name → v {
    ? & & != g_lint 0 != g_lint_recording 0 ( lint_in_top_file )
    { ? == ( nurl_str_get name 0 ) 95 {}
        { : s row ( nurl_str_cat
            ( nurl_str_cat3 name `\t` ( nurl_str_int ( nurl_lex_line lex ) ) )
            ( nurl_str_cat3 `\t` ( nurl_str_int ( nurl_lex_col lex ) ) `\n` ) )
            : s cur ( nurl_sym_get g_lint_syms `binds` )
            ( nurl_sym_def g_lint_syms `binds` ( nurl_str_cat cur row ) ) }
    }
    {}
}

// Parse one "name\tline\tcol" binding row and warn if `name` was never
// read in the current generation. Factored out so the loop stays flat.
@ lint_check_bind s file s row → v {
    : i t1 ( nurl_str_find row `\t` )
    ? < t1 0 {} {
        : i rl ( nurl_str_len row )
        : s nm ( nurl_str_slice row 0 t1 )
        : s tail ( nurl_str_slice row + t1 1 - rl + t1 1 )
        : i t2 ( nurl_str_find tail `\t` )
        ? < t2 0 {} {
            : i tl ( nurl_str_len tail )
            : s ln ( nurl_str_slice tail 0 t2 )
            : s cl ( nurl_str_slice tail + t2 1 - tl + t2 1 )
            : s key ( nurl_str_cat3 ( nurl_str_int g_lint_gen ) ` ` nm )
            ? == 0 ( nurl_str_len ( nurl_sym_get g_lint_reads key ) )
            { ( lint_warn file ( nurl_str_to_int ln ) ( nurl_str_to_int cl )
                ( nurl_str_cat3 `unused binding '` nm
                `' is never read - prefix with '_' or remove it` ) ) }
            {}
        }
    }
}

// At function-body end, warn for every recorded `:` binding never read
// in this function. Reads were tracked unconditionally (including
// inside closures), so a binding used only by a captured closure is
// correctly seen as used.
@ lint_fn_end i lex → v {
    ? & != g_lint 0 ( lint_in_top_file )
    { : s file ( nurl_lex_filename lex )
        : ~ s rest ( nurl_sym_get g_lint_syms `binds` )
        ~ != 0 ( nurl_str_len rest ) {
            : i nl ( nurl_str_find rest `\n` )
            : i rl ( nurl_str_len rest )
            : s row ? < nl 0 rest ( nurl_str_slice rest 0 nl )
            = rest ? < nl 0 `` ( nurl_str_slice rest + nl 1 - rl + nl 1 )
            ( lint_check_bind file row )
        }
    }
    {}
}

// Record an @-decl (function) defined in the top file for the
// unused-function check. `line`/`col` mark the name token.
@ lint_note_fn i lex s name i line i col → v {
    ? & & != g_lint 0 != g_lint_recording 0 ( lint_in_top_file )
    { : s file ( vis_current_src_file )
        : s row ( nurl_str_cat
        ( nurl_str_cat3 name `\t` ( nurl_str_int line ) )
        ( nurl_str_cat
        ( nurl_str_cat3 `\t` ( nurl_str_int col ) `\t` )
        ( nurl_str_cat file `\n` ) ) )
        : s cur ( nurl_sym_get g_lint_syms `fns` )
        ( nurl_sym_def g_lint_syms `fns` ( nurl_str_cat cur row ) ) }
    {}
}

// Parse one "name\tline\tcol\tfile" fn row and warn when it names a
// private (non-`pub`) function in a strict-mode file that was never
// referenced. `main`, `pub` functions, and legacy (no-`pub`) files are
// skipped — in a file that never opts into visibility every @-fn is
// globally callable, so disuse cannot be proved from one compilation.
@ lint_check_fn s row → v {
    : i t1 ( nurl_str_find row `\t` )
    ? < t1 0 {} {
        : i rl ( nurl_str_len row )
        : s nm ( nurl_str_slice row 0 t1 )
        : s r1 ( nurl_str_slice row + t1 1 - rl + t1 1 )
        : i t2 ( nurl_str_find r1 `\t` )
        : i r1l ( nurl_str_len r1 )
        : s ln ( nurl_str_slice r1 0 t2 )
        : s r2 ( nurl_str_slice r1 + t2 1 - r1l + t2 1 )
        : i t3 ( nurl_str_find r2 `\t` )
        : i r2l ( nurl_str_len r2 )
        : s cl ( nurl_str_slice r2 0 t3 )
        : s file ( nurl_str_slice r2 + t3 1 - r2l + t3 1 )
        : s is_pub ( nurl_sym_get g_vis_syms ( nurl_str_cat nm `__pub` ) )
        : s strict ( nurl_sym_get g_vis_syms ( nurl_str_cat file `__strict` ) )
        : s used ( nurl_sym_get g_lint_used nm )
        ? & ! ( seq nm `main` ) & ( seq strict `1` ) & ! ( seq is_pub `1` ) == 0 ( nurl_str_len used )
        { ( lint_warn file ( nurl_str_to_int ln ) ( nurl_str_to_int cl )
            ( nurl_str_cat3 `unused function '` nm
            `' is defined but never called (private to this file)` ) ) }
        {}
    }
}

// After the whole program is compiled (and every deferred generic is
// instantiated, so all call sites have been seen), walk the recorded
// top-file @-decls and report the unused private ones.
@ lint_report_unused_fns → v {
    ? == g_lint 0 {} {
        : ~ s rest ( nurl_sym_get g_lint_syms `fns` )
        ~ != 0 ( nurl_str_len rest ) {
            : i nl ( nurl_str_find rest `\n` )
            : i rl ( nurl_str_len rest )
            : s row ? < nl 0 rest ( nurl_str_slice rest 0 nl )
            = rest ? < nl 0 `` ( nurl_str_slice rest + nl 1 - rl + nl 1 )
            ( lint_check_fn row )
        }
    }
}

// Parse one "path\tline\tcol" import row; warn when none of the
// symbols the imported file defines is referenced (file-scoped key in
// g_lint_used) by the top file itself.
@ lint_check_import s top s row → v {
    : i t1 ( nurl_str_find row `\t` )
    ? < t1 0 { ^ v } {}
    : i rl ( nurl_str_len row )
    : s path ( nurl_str_slice row 0 t1 )
    : s tail ( nurl_str_slice row + t1 1 - rl + t1 1 )
    : i t2 ( nurl_str_find tail `\t` )
    ? < t2 0 { ^ v } {}
    : i tl ( nurl_str_len tail )
    : s ln ( nurl_str_slice tail 0 t2 )
    : s cl ( nurl_str_slice tail + t2 1 - tl + t2 1 )
    : s defs ( nurl_sym_get g_lint_syms ( nurl_str_cat `defs:` path ) )
    // No recorded decls → pure aggregator (re-export surface like
    // stdlib/ext/http_full.nu) or unreadable path; never warn (same
    // exemption as the LSP).
    ? == 0 ( nurl_str_len defs ) { ^ v } {}
    : ~ s drest defs
    : ~ b used F
    ~ & != 0 ( nurl_str_len drest ) ! used {
        : i dt ( nurl_str_find drest `\t` )
        : i dl ( nurl_str_len drest )
        : s nm ? < dt 0 drest ( nurl_str_slice drest 0 dt )
        = drest ? < dt 0 `` ( nurl_str_slice drest + dt 1 - dl + dt 1 )
        ? == 0 ( nurl_str_len nm ) {}
        { ? != 0 ( nurl_str_len ( nurl_sym_get g_lint_used
            ( nurl_str_cat3 top ` ` nm ) ) )
            { = used T } {} }
    }
    ? used {} {
        ( lint_warn top ( nurl_str_to_int ln ) ( nurl_str_to_int cl )
        ( nurl_str_cat3 `unused import: no symbol from '` path
        `' is referenced in this file` ) )
    }
}

// After the whole program is compiled, walk the recorded top-file
// `$` imports and report the unused ones. A top file that defines no
// symbols of its own is a pure aggregator — its imports exist to be
// re-exported, so the report is skipped entirely (LSP parity).
@ lint_report_unused_imports → v {
    ? == g_lint 0 { ^ v } {}
    : s top ( nurl_sym_get g_lint_syms `top` )
    ? == 0 ( nurl_str_len ( nurl_sym_get g_lint_syms ( nurl_str_cat `defs:` top ) ) )
    { ^ v } {}
    : ~ s rest ( nurl_sym_get g_lint_syms `imports` )
    ~ != 0 ( nurl_str_len rest ) {
        : i nl ( nurl_str_find rest `\n` )
        : i rl ( nurl_str_len rest )
        : s row ? < nl 0 rest ( nurl_str_slice rest 0 nl )
        = rest ? < nl 0 `` ( nurl_str_slice rest + nl 1 - rl + nl 1 )
        ( lint_check_import top row )
    }
}

// One hex digit as its ASCII code (0-9 → '0'-'9', 10-15 → 'A'-'F').
@ __hex_digit_ch i d → i {
    ? < d 10 + 48 d + 55 d
}

// Encode [pos,end) of val as an LLVM IR c"..." payload: printable
// ASCII passes through, everything else (and '"' '\') becomes \HH.
// Iterative on purpose — a per-character recursion overflowed the
// stack on literals past ~124 KB (embedded assets are that big).
@ encode_str s val i pos i end → s {
    : i n - end pos
    // worst case every byte escapes to three chars, plus NUL
    : s out # s ( malloc + * n 3 1 )
    : *u op # *u out
    : ~ i w 0
    : ~ i p pos
    ~ < p end {
        : i c ( nurl_str_get val p )
        ? | | < c 32 > c 126 | == c 34 == c 92 {
            = . op w # u 92 = w + w 1
            = . op w # u ( __hex_digit_ch / c 16 ) = w + w 1
            = . op w # u ( __hex_digit_ch % c 16 ) = w + w 1
        } {
            = . op w # u c = w + w 1
        }
        = p + p 1
    }
    = . op w # u 0
    out
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

// Like gen_str_lit but for a compiler-synthesised message (no lexer token):
// registers a deferred @.str.N global (emitted after the function, so it is
// safe to call mid-body) and emits a getelementptr to its i8*. Used for
// runtime panic messages such as the div-by-zero guard.
@ emit_deferred_cstr i cg s msg → s {
    : s enc ( encode_str msg 0 ( nurl_str_len msg ) )
    : i totlen + ( nurl_str_len msg ) 1
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
    res
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
    ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty lty ) )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty lty ) ) ( nurl_print `* null, i64 1\n` )
    ( nurl_print `  ` ) ( nurl_print r1 )
    ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty lty ) )
    ( nurl_print `* ` ) ( nurl_print r0 ) ( nurl_print ` to i64\n` )
    ( nurl_set_last_type `i64` )
    r1
}

// Emit the `ret` terminator (or branch to the defer chain) after owned-
// resource drops. Shared by the normal return path and the bare-`^`
// void early-return. A function declared `→ v` ALWAYS emits `ret void`;
// `lt`/`val` are the returned value's LLVM type / SSA name (both empty
// for a bare void return). Keeps the void/non-void `ret` choice keyed on
// the FUNCTION's return type, not just the value type — so a stray value
// can never lower to `ret i64 …` out of a `void` function.
@ gen_ret_term i lex i syms i cg s lt s val s skip s skip_str_ptr s skip_user_ptr s skip_struct_ptr s ret_ident → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    : s fn_rt ( nurl_sym_get syms `__fn_ret_ty__` )
    ? != 0 ( nurl_str_len dtop )
    {  // defers active: store return value then branch to defer chain
        ? ! ( seq lt `void` )
        { : s rvp ( nurl_sym_get syms `__ret_val__` )
            ( nurl_print `  store ` ) ( nurl_print ( nurl_llty lt ) ) ( nurl_print ` ` )
            ( nurl_print val ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty lt ) )
            ( nurl_print `* ` ) ( nurl_print rvp ) ( nurl_print `\n` )
        }
        {}
        ( nurl_print `  br label %` ) ( nurl_print dtop ) ( emit_dbg_eol )
    }
    {  // no defers: drop owned slices then direct return
        ( mem_drop_owned syms cg skip )
        ? != 0 g_auto_drop_strings
        { ( mem_drop_owned_strings syms cg skip_str_ptr )
            ( mem_drop_owned_struct_fields syms cg skip_struct_ptr )
            ( mem_drop_user_drops syms cg skip_user_ptr )
        }
        {}
        ( mem_own_closure_remove syms ret_ident )
        ( mem_drop_closure_envs syms cg )
        ? | ( seq lt `void` ) ( seq fn_rt `void` )
        { ( emit_call_term `ret void` ) }
        { ( nurl_print `  ret ` ) ( nurl_print ( nurl_llty lt ) )
            ( nurl_print ` ` ) ( nurl_print val ) ( emit_dbg_eol ) }
    }
}

@ gen_ret i lex i syms i cg → s {
    // Cascade guard: a `^` reached here while parsing a value operand
    // (g_ret_forbidden set by gen_operand / a `?`-condition / `??`-
    // scrutinee / a return value) means a preceding fixed-arity prefix
    // operator was short an argument and swallowed this `^`. Emitting a
    // `ret` would terminate the block mid-expression, leaving the
    // operator's result as dead code after the terminator — a silent
    // miscompile (e.g. `: i x + 1` / `^ a` lowered `+ 1 (^ a)` to
    // `ret %a` then a dead `add`). Reject it on the `^`. Closes the
    // within-statement half of the prefix-arity cascade gotcha.
    ? != 0 g_ret_forbidden
    { ( die lex `'^' (return) cannot appear here — it is being read as a value operand. A preceding prefix operator is short an argument and consumed this '^': every NURL operator has fixed arity and no closing bracket, so a missing operand silently swallows what follows. Count the operands on the operator before this '^'.` ) }
    {}
    // Borrow checker: source line of the `^` token.
    : i bck_line ( nurl_lex_line lex )
    ( nurl_lex_advance lex )
    // Bare `^` — a return with no value expression (the next token ends
    // the statement/block). Legal ONLY in a `→ v` function, where it is
    // an early return that emits `ret void`. In a value-returning
    // function it is an error (the caller would get garbage), and is
    // reported here rather than letting gen_operand fail with the
    // generic "value expression required" cascade message.
    : i __ret_nt ( nurl_lex_type lex )
    ? | | == __ret_nt TT_RBRACE == __ret_nt TT_EOF == __ret_nt TT_SEMICOL
    { : s __ret_frt ( nurl_sym_get syms `__fn_ret_ty__` )
        ? ( seq __ret_frt `void` )
        { ( bck_record `ret` `` bck_line )
            ( gen_ret_term lex syms cg `void` `` `` `` `` `` `` )
            ( nurl_set_last_type `void` )
            = g_did_ret 1
            ^ `` }
        { ( die lex ( nurl_str_cat ( nurl_str_cat
            `bare '^' (return) but this function returns '` ( llvm_to_nurl __ret_frt ) )
            `' — a '^' here must be followed by a return value of that type` ) ) }
    }
    {}
    // The `^ ?? value { F e → {…} T m → {…} }` shape looks
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
    // literal capturing a binding by pointer (docs/MEMORY.md §2.3).
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
    // Snapshot whether the return expression is a direct parenthesised
    // call — `^ ( f … )`. Used below to propagate string-return
    // ownership: a direct call's `__last_call_ret_owned__` is always
    // (re)set by the OUTERMOST call's emit site, so consulting it is
    // exact for this shape and never stale (any other expression shape
    // skips the check entirely).
    : b ret_is_direct_call == ( nurl_lex_type lex ) TT_LPAREN
    // A4c: reset the agg / call struct-ownership side-channels so the
    // return-value analysis below observes only what THIS expression
    // sets (a stale `@ T {…}` from an earlier statement must not leak
    // into a `^ ( plain_struct_fn )` return).
    ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
    ( nurl_sym_def syms `__last_call_ret_struct_fields__` `` )
    ( nurl_sym_def syms `__last_agg_param_idents__` `` )
    // Return-escape inference (docs/MEMORY.md §2.8): snapshot whether
    // this return is a bare identifier (`^ p`) so the post-gen_operand
    // check can tell a direct parameter passthrough from a derived
    // expression (`^ + p 1`, `^ ( f p )`).
    : i ret_first_tt ( nurl_lex_type lex )
    : s ret_first_val ( nurl_lex_val lex )
    : s val ( gen_operand lex syms cg )
    // If the returned value WAS exactly that bare identifier and it
    // names a parameter, record the parameter index: callers then learn
    // this function may return that argument, propagating a passed-in
    // stack reference out through the call result.
    ? & ( is_ident_tok ret_first_tt )
    ( seq ( nurl_sym_get syms `__last_ident_name__` ) ret_first_val )
    { ( bck_record_ret_param syms ret_first_val ) }
    {}
    // §2.8 (aggregate form): `^ @ T { … param … }` embeds parameters as
    // fields — the returned struct hands each one back out, so record
    // them too. gen_agg_lit published the embedded parameter names.
    ? & != g_borrowck 0 == ret_first_tt TT_AT
    { : ~ s __rp_rest ( nurl_sym_get syms `__last_agg_param_idents__` )
        ~ != 0 ( nurl_str_len __rp_rest ) {
            : s __rp_w ( str_first_word __rp_rest )
            = __rp_rest ( str_skip_word __rp_rest )
            ( bck_record_ret_param syms __rp_w )
        } }
    {}
    // XOR confusion (critic v0.9.0 §1): `^ X Y` on the same line is
    // almost always the user thinking `^` is XOR. `^^` (two adjacent
    // carets, no space) IS XOR; `^ X` returns X and any tail tokens
    // are dead code. Heuristic: post-expression next-token on the
    // same line as `^` AND not a statement/expression terminator.
    : i __xor_nt ( nurl_lex_type lex )
    : i __xor_nl ( nurl_lex_line lex )
    // TT_LBRACE is excluded because `^ X { ... }` is the canonical
    // shape for the then-arm of a `?` ternary whose else-arm follows
    // on the same line: `? cond ^ then_val { else_block }`.
    : b __xor_blocks | | | | | | | == __xor_nt TT_COLON == __xor_nt TT_EQ
    == __xor_nt TT_SEMICOL == __xor_nt TT_RBRACE == __xor_nt TT_RPAREN
    == __xor_nt TT_RBRACK == __xor_nt TT_LBRACE == __xor_nt TT_EOF
    // Suppressed inside a `??` arm body: there the token after `^ X` is the
    // next arm's pattern (`T x → ^ x  F _ → …`), not a stray XOR operand.
    ? & & == __xor_nl bck_line ! __xor_blocks == g_in_match_arm 0
    { ( warn lex `'^' is the return operator; did you mean '^^' for XOR? (Two adjacent carets, no space between them)` ) }
    {}
    // Borrow checker: record this return statement.
    ( bck_record `ret` `` bck_line )
    // Defensive: clear any residual pending flag (gen_expr may have
    // taken a different path — e.g. a literal or operator — that
    // never reached gen_call to consume it).
    ( nurl_sym_def syms `__tail_call_pending__` `` )
    : s lt ( nurl_get_last_type )
    // Escape analysis: warn if the returned value
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
        `) — match arms contain '^' so '?? …' is statement-form, not an expression. Refactor to ': ~ T rc init / ?? mr { … = rc v } / ^ rc'.`
        `) — likely a conditional with incompatible branch types`
        ( die lex ( nurl_str_cat `return expression has no value (expected `
        ( nurl_str_cat ( llvm_to_nurl fn_rt ) hint ) ) ) }
    {}
    // Inverse of the above: the function is declared `→ v` (returns
    // nothing) but `^` was handed a real value. Lowering it would emit
    // `ret <ty> <val>` out of a `void` LLVM function — invalid IR that
    // historically only clang caught (`ret i64 0` from `→ v`). Reject it
    // here; the cure is a bare `^` (early return) or a non-void type.
    ? & ! ( seq lt `void` ) ( seq fn_rt `void` )
    { ( die lex ( nurl_str_cat ( nurl_str_cat
        `this function is declared '→ v' (returns nothing) but '^' is given a value of type '` ( llvm_to_nurl lt ) )
        `' to return — use a bare '^' to return early, or declare a return type` ) ) }
    {}
    // Return-type agreement (narrow, never-valid clashes only — mirrors the
    // binary-operator check). NURL has no implicit conversions, so returning a
    // float where a non-float is declared (or vice versa), or a pointer/string
    // where a non-pointer scalar is declared, used to emit `ret i64 <double>` /
    // `ret i64 i8* …` that nurlc accepted (rc 0) and only clang rejected
    // ("value doesn't match function result type"). Only these two directions
    // are flagged so the null-as-`0` idiom (`^ 0` from a `*T`-returning fn) and
    // loose pointer-to-pointer returns stay valid.
    ? & & != 0 ( nurl_str_len fn_rt ) ! ( seq lt `void` ) ! ( seq fn_rt `void` )
    { : b ret_vf | ( seq lt `double` ) ( seq lt `float` )
        : b ret_df | ( seq fn_rt `double` ) ( seq fn_rt `float` )
        ? | != ret_vf ret_df & ( is_ptr_ty lt ) ! ( is_ptr_ty fn_rt )
        { ( die lex ( nurl_str_cat ( nurl_str_cat4
            `return value type '` lt `' does not match the declared return type '` fn_rt )
            `' — NURL has no implicit conversions; return a value of the declared type or convert with '# T expr'` ) ) }
        {}
        // Return the wrong named struct by value (the return-position dual of
        // the call-site struct check): `^ b` from a `→ A` fn where b is a B.
        ? ( __arg_named_struct_mismatch lt fn_rt )
        { ( die lex ( nurl_str_cat ( nurl_str_cat4
            `return value type '` lt `' does not match the declared return type '` fn_rt )
            `' — wrong struct type returned by value (the fields would be silently reinterpreted)` ) ) }
        {}
    }
    {}
    // Determine which owned-slice binding (if any) is escaping as the return value.
    // Ownership transfers only when the return type is itself a slice AND the
    // returned expression resolved to a simple identifier load.
    : s ret_ident ( nurl_sym_get syms `__last_ident_name__` )
    // `^ ( f … x … )`: the returned value is the CALL's result — the
    // argument scan merely left `x` in __last_ident_name__, and the
    // callee does NOT take ownership of its arguments, so cancelling
    // x's scheduled drop here would leak it on every such return. The
    // one aliasing shape — a callee that returns a borrow of its
    // argument (ret_borrow summary / vec_get*) — keeps the skip:
    // dropping the source would dangle the returned alias
    // (conservative: worst case leak, never UAF).
    : b ret_arg_alias | ! ret_is_direct_call
    != 0 ( nurl_str_len ( nurl_sym_get syms `__last_value_borrow__` ) )
    : s skip ? & & ( mem_is_slice_ty lt ) ( str_contains_word ( nurl_sym_get syms `__owned_slices__` ) ret_ident )
    ret_arg_alias
    ret_ident
    ``
    // Phase 2B: owned-string escape analysis on the returned identifier.
    : ~ s skip_str_ptr ``
    : ~ s skip_user_ptr ``
    ? != 0 g_auto_drop_strings
    { : s rid_ptr ( nurl_sym_get syms ( nurl_str_cat ret_ident `__ptr` ) )
        = skip_str_ptr ? & & ( seq ( nurl_llty lt ) `i8*` ) ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) rid_ptr )
        ret_arg_alias
        rid_ptr
        ``
        ? != 0 ( nurl_str_len skip_str_ptr )
        { ( nurl_sym_def syms `__fn_ret_str_owned__` `1` ) }
        {}
        // `^ ( f … )` returning a fresh owned string: the value never
        // lived in a local (nothing to skip), but the OWNERSHIP must
        // still propagate to this function's `__ret_owned` marker —
        // otherwise `: s x ( g )` off a `@ g → s { ^ ( nurl_str_cat … ) }`
        // composes helpers into a leak. `__last_call_ret_owned__` was
        // (re)set by the outermost call's emit site just above.
        ? & & ret_is_direct_call ( seq ( nurl_llty lt ) `i8*` )
        ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` )
        { ( nurl_sym_def syms `__fn_ret_str_owned__` `1` ) }
        {}
        = skip_user_ptr ? & ( str_contains_word ( nurl_sym_get syms `__user_drops__` ) rid_ptr )
        ret_arg_alias
        rid_ptr
        ``
    }
    {}
    // A4c: owned-struct-field ownership transfer. Compute the returned
    // struct binding to skip-drop (and publish `__fn_ret_struct_owned__`
    // for the caller to re-register). The binding path only applies
    // when the returned value can BE that binding (see ret_arg_alias) —
    // a direct call's fresh struct rides __last_call_ret_struct_fields__.
    : s xfer_ident ? ret_arg_alias ret_ident ``
    : ~ s skip_struct_ptr ``
    ? != 0 g_auto_drop_strings
    { = skip_struct_ptr ( mem_ret_struct_transfer syms lt xfer_ident ) }
    {}
    ? != 0 ( nurl_str_len skip )
    { ( nurl_sym_def syms `__fn_ret_owned__` `1` ) }
    {}
    // Borrow provenance: if the returned value is a borrow (derived from a
    // parameter), this function returns a borrow — callers must NOT
    // auto-drop a `:`-binding off it.
    ? != 0 ( nurl_str_len ( nurl_sym_get syms `__last_value_borrow__` ) )
    { ( nurl_sym_def syms `__fn_ret_borrow__` `1` ) }
    {}
    ( gen_ret_term lex syms cg lt val skip skip_str_ptr skip_user_ptr skip_struct_ptr ret_ident )
    ( nurl_set_last_type `void` )
    = g_did_ret 1
    val
}

@ gen_unary_not i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s v ( gen_operand lex syms cg )
    ( die_if_void lex v `logical-not '!'` )
    // '!' is logical not over b (i1) ONLY. Without this check a non-bool
    // operand reaches the xor below and emits 'xor i1 <i64 reg>' — an
    // LLVM-level type error escaping the frontend (classic trigger: an
    // i-typed binding initialised with T/F, then '! flag').
    : s ot ( nurl_get_last_type )
    ? ! ( seq ot `i1` )
    { : s msg ( nurl_str_cat `operator '!' requires a b operand — got ` ( llvm_to_nurl ot ) )
        ( die lex ( nurl_str_cat msg `. Declare truth-value bindings as 'b', not 'i' (': ~ b flag F'), or test an integer explicitly ('== x 0')` ) )
    }
    {}
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
: ~ i g_stmt_line 0

// g_stmt_col — column of the current statement's first token, captured
// alongside g_stmt_line. `die_stmt` anchors a diagnostic here when the
// clash is only detected after the statement's operands were consumed
// (e.g. a bind's initializer type mismatch, where the lexer has already
// advanced to the next statement).
: ~ i g_stmt_col 0

// die_stmt: like die, but anchored at the CURRENT statement's start
// (g_stmt_line / g_stmt_col) rather than the lexer's live position. Use it
// for a clash detected only after the statement's operands were consumed —
// e.g. a bind/assign initializer type mismatch, where the lexer has already
// advanced to the next statement and `die lex` would blame the wrong line.
// No caret/source-line echo (the anchor's line text isn't retained), but the
// `file:line:col: msg` prefix points at the real culprit. `lex` supplies the
// filename only.
@ die_stmt i lex s msg → v {
    : s loc ( nurl_str_cat ( nurl_lex_filename lex )
    ( nurl_str_cat `:` ( nurl_str_cat ( nurl_str_int g_stmt_line )
    ( nurl_str_cat `:` ( nurl_str_int g_stmt_col ) ) ) ) )
    ( nurl_eprintln ( nurl_str_cat3 loc `: ` msg ) )
    ( __diag_abort )
}

// die anchored at an EXPLICIT (line, col) in the current lexer's file,
// with the full caret shape — for a check that fires after the lexer
// has already advanced past the offending token (e.g. gen_ident's
// undefined-identifier check runs one token late; the caller captured
// the identifier's own position before advancing).
@ die_pos i lex i line i col s msg → v {
    : s loc ( nurl_str_cat ( nurl_lex_filename lex )
    ( nurl_str_cat `:` ( nurl_str_cat ( nurl_str_int line )
    ( nurl_str_cat `:` ( nurl_str_int col ) ) ) ) )
    ( nurl_eprintln ( nurl_str_cat3 loc `: ` msg ) )
    ( nurl_eprintln ( nurl_lex_line_text_at lex line ) )
    ( nurl_eprintln ( nurl_diag_caret col ) )
    ( __diag_abort )
}

// g_stmt_bare_lit — set by gen_stmt to 1 when the statement it just
// parsed was a bare numeric/string LITERAL in expression position (no
// side effect). The block iterators (gen_block_stmts / gen_block_ret)
// read it to reject such a statement when its value is discarded — a
// literal in non-return position is dead, and the usual cause is a
// prefix operator handed one operand too many (a dangling operand),
// e.g. `& x 255 0x40` parses as `& x 255` and silently drops `0x40`.
// Match arms whose body is a bare literal call gen_stmt directly (not
// via a block iterator), so this never false-flags an arm value.
: ~ i g_stmt_bare_lit 0

// g_stmt_bare_value — the literal flag's general sibling (critic A2,
// the last silent prefix-arity cascade): set by gen_stmt to 1 when the
// statement it just parsed produced a VALUE without being a call or
// control flow — a bare local/param/const identifier, an operator
// expression (`+ a 1`), a `#` cast, a `.` field read, an `@` aggregate
// literal. Such a statement's value is discarded; the block iterators
// WARN (not die — unlike a literal, these shapes at least name real
// bindings) unless it is a value-block's final expression (the block
// result). Recomputed unconditionally at the END of every gen_stmt
// from the statement's own leading token + result type, so nested
// blocks parsed mid-statement cannot leak a stale flag outward.
: ~ i g_stmt_bare_value 0

// __tok_label — a human-readable name for a token that turned up where
// a value expression was required. Used only on the diagnostic path.
@ __tok_label i tt s val → s {
    ? == tt TT_COLON { ^ `':' (a ':' binding starts here)` } {}
    ? == tt TT_EQ { ^ `'=' (an assignment starts here)` } {}
    ? == tt TT_SEMICOL { ^ `';' (a ';' defer starts here)` } {}
    ? == tt TT_RBRACE { ^ `'}' (the enclosing block ends here)` } {}
    ? == tt TT_RPAREN { ^ `')'` } {}
    ? == tt TT_RBRACK { ^ `']'` } {}
    ? == tt TT_LBRACE { ^ `'{'` } {}
    ? == tt TT_LPAREN { ^ `'('` } {}
    ? == tt TT_LBRACK { ^ `'['` } {}
    ? == tt TT_AT { ^ `'@'` } {}
    ? == tt TT_EOF { ^ `end of input` } {}
    ? == tt TT_ARROW { ^ `'->'` } {}
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

// gen_operand: parse a VALUE sub-expression that will be consumed by an
// enclosing operator / call / condition. Sets g_ret_forbidden so a `^`
// (return) appearing here — the tell-tale of a short-an-argument prefix
// cascade — is rejected by gen_ret rather than emitting a stray `ret`.
// Save/restore makes nesting and the control-flow reset points compose.
@ gen_operand i lex i syms i cg → s {
    : i saved g_ret_forbidden
    = g_ret_forbidden 1
    : s v ( gen_expr lex syms cg )
    = g_ret_forbidden saved
    ^ v
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
    : s lv ( gen_operand lex syms cg )
    : s lt ( nurl_get_last_type )
    ? ! ( seq lt `i1` )
    { ( die lex `operator || requires bool operands — left operand has non-bool type` ) }
    {}
    : s left_lbl ( nurl_sym_get syms `__cur_lbl__` )
    ^ ( gen_logical_or lv left_lbl lex syms cg )
}

@ gen_andand i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s lv ( gen_operand lex syms cg )
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
    ( die_if_void lex v `complement '~'` )
    : s res ( nurl_cg_reg cg )
    ? ( seq lt `double` )
    { ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ` = fneg double ` ) ( nurl_print v ) ( nurl_print `\n` )
    }
    { ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ` = xor ` ) ( nurl_print ( nurl_llty lt ) )
        ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `, -1\n` )
    }
    res
}

// load_var: emit a load instruction and return the result register.
@ load_var i cg s lt s ptr → s {
    : s res ( nurl_cg_reg cg )
    : s ll ( nurl_llty lt )
    ( nurl_print `  ` ) ( nurl_print res )
    ( nurl_print ` = load ` ) ( nurl_print ll )
    ( nurl_print `, ` ) ( nurl_print ll )
    ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
    res
}

@ gen_ident i lex i syms i cg → s {
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s name ( nurl_lex_val lex )
        // The identifier's own position, captured before the advance —
        // the undefined-identifier check below fires after it, and a
        // live-lexer diagnostic would blame the NEXT token (die_pos).
        : i __id_line ( nurl_lex_line lex )
        : i __id_col ( nurl_lex_col lex )
        ( nurl_lex_advance lex )
        // Borrow checker: every value-position identifier is a read.
        ( bck_note_read name )
        // Closure-env reclamation: a value-position load disqualifies a
        // parameter from the invoke-only set (§7.4). The callee position
        // of a call never reaches gen_ident, so a parameter that is only
        // ever invoked stays invoke-only.
        ( bck_mark_param_valueread syms name )
        // Closure-env reclamation: loading a tracked `:`-bound closure as
        // a VALUE means it escapes (returned, stored, decomposed, captured)
        // — drop it from the owned set so it is not freed at scope exit.
        // A call ARGUMENT load is exempt (`__in_call_arg__`): gen_call
        // decides borrow-vs-escape from the callee's invoke-only set; an
        // invocation's callee never reaches gen_ident at all.
        ? & == 0 ( nurl_str_len ( nurl_sym_get syms `__in_call_arg__` ) )
        ( str_contains_word ( nurl_sym_get syms `__owned_closure_envs__` ) name )
        { ( mem_own_closure_remove syms name ) }
        {}
        // Lint: mark the name as read (unused-binding) and referenced
        // (unused-function). Unlike bck_note_read this is NOT suppressed
        // inside closures, so a binding captured by a closure counts.
        ( lint_note_read name )
        ( lint_note_used name )
        // The void keyword `v` in value position (canonically `^ v` from
        // a void function) denotes the unit/void value — UNLESS a binding
        // of the same name shadows it (e.g. `: f v ( strtod … ) ^ v`).
        // Without this, an unshadowed `v` fell through to the generic
        // ident path, which set last_type to i64 and emitted `%v` — an
        // undefined SSA value at the wrong type, silently invalid IR.
        ? & ( seq name `v` ) == 0 ( nurl_str_len ( nurl_sym_get syms name ) )
        { ( nurl_sym_def syms `__last_ident_name__` name )
            ( nurl_set_last_type `void` )
            ^ `void` }
        {}
        : s lt ( nurl_sym_get syms name )
        ( nurl_set_last_type ? == 0 ( nurl_str_len lt ) `i64` lt )
        : s ptr ( nurl_sym_get syms ( nurl_str_cat name `__ptr` ) )
        : s glb ( nurl_sym_get syms ( nurl_str_cat name `__global` ) )
        // Bare `@-fn` names don't auto-coerce to a
        // `(@ R P*)` closure parameter. A bare @-fn ident used as a
        // value (i.e. NOT as a call's callee — gen_call's own path
        // consumes the name before reaching here) currently emits IR
        // that clang rejects with `use of undefined value '%name'`,
        // because nurlc's fallback returns `%name` rather than a
        // closure struct. Detect: name has `__src_file` set (i.e. is
        // a @-fn) AND no `__ptr` (not a local) AND no `__global`
        // (not a const / enum variant). Die with the canonical
        // wrap-in-closure-literal cure.
        ? & & & == 0 ( nurl_str_len ptr ) == 0 ( nurl_str_len glb ) == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat name `__param` ) ) ) != 0 ( nurl_str_len ( nurl_sym_get g_vis_syms ( nurl_str_cat name `__src_file` ) ) )
        { : s tail ( nurl_str_cat name ` args ) }'.` )
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
        // Borrow provenance: loading a `__borrow`-marked binding yields a
        // borrow; any other ident load yields a non-borrow (resets the flag).
        ( nurl_sym_def syms `__last_value_borrow__` ( nurl_sym_get syms ( nurl_str_cat name `__borrow` ) ) )
        // Signedness rides the binding's stored type itself (A1) —
        // `lt` above is the internal repr (`u8` vs `i8` distinct), so
        // the set_last_type call already propagated it.
        // Root-cause guard for the arity-cascade footgun (critic.md §4).
        // Reaching this point means the name is none of: a local / match-
        // payload / loop / inout / closure-capture binding (all carry a
        // `__ptr`), a const or enum variant (`__global`), the void literal
        // `v` (handled above), or a bare @-fn (dies above). The only
        // legitimate remaining case is a by-value function parameter, which
        // resolves to its SSA register `%name` and carries `__param`. Any
        // other name is simply not in scope. The old code fell through to
        // `( nurl_str_cat `%` name )` unconditionally, emitting an undefined
        // SSA value (`%a`) that nurlc accepted with status 0 and only clang
        // later rejected. Reject it in the front-end so the diagnostic
        // lands on the source, making GOTCHAS.md's "every trap is a compiler
        // diagnostic" claim true end-to-end.
        ? & & == 0 ( nurl_str_len ptr ) == 0 ( nurl_str_len glb )
        == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat name `__param` ) ) )
        { : s __sugg ( __suggest_ident syms name )
            ? != 0 ( nurl_str_len __sugg )
            { ( die_pos lex __id_line __id_col ( nurl_str_cat ( nurl_str_cat3 `use of undefined identifier '` name `' — did you mean '` )
                ( nurl_str_cat3 __sugg `'? No binding, parameter, constant, enum variant, or ` `function with this name is in scope` ) ) ) }
            { ( die_pos lex __id_line __id_col ( nurl_str_cat3 `use of undefined identifier '` name `' — no binding, parameter, constant, enum variant, or function with this name is in scope` ) ) } }
        {}
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
            ` a prefix operator is short an argument: every NURL operator has fixed arity and no closing bracket, so a missing operand silently consumes whatever follows. See docs/LIMITATIONS.md -> Grammar.` ) ) }
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
    : ~ s lv ( gen_operand lex syms cg )
    : s lt ( nurl_get_last_type )
    : ~ s rv ( gen_operand lex syms cg )
    : s rt ( nurl_get_last_type )
    ( die_if_void lex lv `binary operator's left` )
    ( die_if_void lex rv `binary operator's right` )
    : s res ( nurl_cg_reg cg )
    : b isf | ( seq lt `double` ) ( seq lt `float` )
    // `^^` (XOR) is integer/bool-only — LLVM has no float `xor`.
    ? & == tt TT_CARETCARET isf
    { ( die lex `operator '^^' (XOR) requires integer or bool operands, not a float` ) }
    {}
    // Unsigned operand path. Signedness is IN the type repr (A1): `u8`
    // stays distinct from signed `i8` end to end, so the operand types
    // themselves say whether to pick `udiv`/`urem`/`lshr`/`icmp u*`.
    // NURL is strongly typed (lt == rt for arithmetic operands), so the
    // OR over both operands is defensive against asymmetric paths
    // (e.g. an i64 literal mixed with a u64 binding).
    : b isu | ( ty_is_unsigned lt ) ( ty_is_unsigned rt )
    : s ins ( binop_instr tt isf isu )
    // Pointer comparison coercion. LLVM forbids `icmp <op> i8* %p, 0`
    // (integer constant at pointer type) and rejects comparing two
    // differently-typed pointers. For comparison operators, ptrtoint
    // any pointer operand to i64 and compare in i64 — handles null-
    // checks (`== raw 0`), `!= ptr 0`, and pointer↔pointer equality
    // uniformly. ptrtoint is a no-op at the machine level, so this is
    // free. Arithmetic ops are untouched.
    : b is_cmp | & >= tt TT_LT <= tt TT_GE | == tt TT_EQEQ == tt TT_NE
    // Operand-type agreement. NURL has NO implicit numeric conversions, so the
    // two operands of an operator must already share a type (the "lt == rt for
    // arithmetic operands" invariant noted above). Mixing an int and a float
    // (`+ 1 1.0`, `* 2.0 3`, `== 1 1.0`), or a pointer/string and an integer in
    // an arithmetic op (`+ `a` 1`), used to emit `add i64 1, 1.0` / `add i64
    // i8* …` — IR nurlc accepted (rc 0) and only clang rejected ("floating
    // point constant invalid for type" / "integer constant must have integer
    // type"). Reject at the source. (Comparison ops stay exempt for the
    // pointer cases — the ptrtoint coercion below compares `== ptr 0` and
    // ptr↔ptr in i64; only the float/non-float split is enforced for them.)
    : b lf | ( seq lt `double` ) ( seq lt `float` )
    : b rf | ( seq rt `double` ) ( seq rt `float` )
    ? != lf rf
    { ( die lex ( nurl_str_cat ( nurl_str_cat4
        `operator mixes a float and a non-float operand: left is '` lt
        `', right is '` rt )
        `' — NURL has no implicit numeric conversions; make both the same type (cast with '# f expr' or '# i expr')` ) ) }
    {}
    : b lp ( is_ptr_ty lt )
    : b rp ( is_ptr_ty rt )
    ? & ! is_cmp != lp rp
    { ( die lex ( nurl_str_cat ( nurl_str_cat4
        `arithmetic operator mixes a pointer/string and a non-pointer operand: left is '` lt
        `', right is '` rt )
        `' — operator-level pointer arithmetic is not supported; index with '. ptr idx' or convert explicitly` ) ) }
    {}
    // Bool (i1) vs non-bool. NURL has no implicit bool↔int conversion, so an
    // operator with exactly one i1 operand emitted e.g. `icmp slt i1 %f, %n`
    // (the other a wider integer) — IR only clang/llvm-as rejected. A CONSTANT
    // operand is fine: it reinterprets to the other side's width (a bool
    // literal `T`/`F` → 0/1 fits i64 in `== v T`; an int literal 0/1 fits i1 in
    // `== flag 0`). The genuine bug is two NON-constant registers of disagreeing
    // bool/int width — detected by both values being SSA registers (`%…`).
    : b l_i1 ( seq lt `i1` )
    : b r_i1 ( seq rt `i1` )
    ? & != l_i1 r_i1 & == ( nurl_str_get lv 0 ) 37 == ( nurl_str_get rv 0 ) 37
    { ( die lex ( nurl_str_cat ( nurl_str_cat4
        `operator mixes a bool (i1) and a non-bool operand: left is '` lt
        `', right is '` rt )
        `' — NURL has no implicit bool↔int conversion; cast one side ('# i expr')` ) ) }
    {}
    : ~ s cmp_ty lt
    ? & is_cmp | ( is_ptr_ty lt ) ( is_ptr_ty rt ) {
        ? ( is_ptr_ty lt ) {
            : s lvi ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print lvi ) ( nurl_print ` = ptrtoint ` )
            ( nurl_print ( nurl_llty lt ) ) ( nurl_print ` ` ) ( nurl_print lv ) ( nurl_print ` to i64\n` )
            = lv lvi
        } {}
        ? ( is_ptr_ty rt ) {
            : s rvi ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print rvi ) ( nurl_print ` = ptrtoint ` )
            ( nurl_print ( nurl_llty rt ) ) ( nurl_print ` ` ) ( nurl_print rv ) ( nurl_print ` to i64\n` )
            = rv rvi
        } {}
        = cmp_ty `i64`
    } {}
    // Integer division / remainder by zero is LLVM UB (SIGFPE on native, a
    // trap on wasm; INT_MIN / -1 likewise). NURL is a safe language, so guard
    // the divisor and panic with a clear message instead of trapping. Float
    // div/rem (fdiv/frem) is IEEE-defined (±inf / NaN) and left untouched —
    // only sdiv/udiv/srem/urem get the check.
    ? & ! isf | == tt TT_SLASH == tt TT_PERCENT
    { : s __dz ( nurl_cg_reg cg )
        : s __lz ( nurl_cg_lbl cg `divzero` )
        : s __lo ( nurl_cg_lbl cg `divok` )
        ( nurl_print `  ` ) ( nurl_print __dz )
        ( nurl_print ` = icmp eq ` ) ( nurl_print ( nurl_llty cmp_ty ) ) ( nurl_print ` ` )
        ( nurl_print rv ) ( nurl_print `, 0\n` )
        ( nurl_print `  br i1 ` ) ( nurl_print __dz )
        ( nurl_print `, label %` ) ( nurl_print __lz )
        ( nurl_print `, label %` ) ( nurl_print __lo ) ( nurl_print `\n` )
        ( emit ( nurl_str_cat __lz `:` ) )
        : s __dmsg ( emit_deferred_cstr cg ? == tt TT_SLASH `division by zero` `remainder by zero` )
        ( nurl_print `  call void @nurl_panic(i8* ` ) ( nurl_print __dmsg ) ( nurl_print `)\n` )
        ( nurl_print `  unreachable\n` )
        ( emit ( nurl_str_cat __lo `:` ) )
        ( nurl_sym_def syms `__cur_lbl__` __lo )
    }
    {}
    ( nurl_print `  ` ) ( nurl_print res ) ( nurl_print ` = ` )
    ( nurl_print ins ) ( nurl_print ` ` )
    ( nurl_print ( nurl_llty cmp_ty ) ) ( nurl_print ` ` )
    ( nurl_print lv ) ( nurl_print `, ` ) ( nurl_print rv ) ( nurl_print `\n` )
    // The result's signedness rides its type: keep the unsigned
    // spelling when either operand contributed it, so a nested binop
    // ( + a + b c ) emits the right ops for the outer +.
    ? | & >= tt TT_LT <= tt TT_GE | == tt TT_EQEQ == tt TT_NE
    ( nurl_set_last_type `i1` )
    ( nurl_set_last_type ? isu ( ty_to_unsigned lt ) lt )
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
    // Check type compatibility. Compare the LOWERED types: `&`/`|` are
    // sign-agnostic OPERATIONS, so mixing a u8 with a signed i8 (or a
    // u64 with an i64 literal) stays legal, exactly as before A1 made
    // the unsigned spellings distinct.
    ? ! ( seq ( nurl_llty lt ) ( nurl_llty rt ) )
    { : s op_name ? == tt TT_AMP `&` `|`
        : s msg1 ( nurl_str_cat `operator ` ( nurl_str_cat op_name ` requires matching types — got ` ) )
        : s msg2 ( nurl_str_cat ( llvm_to_nurl lt ) ( nurl_str_cat ` and ` ( llvm_to_nurl rt ) ) )
        ( die lex ( nurl_str_cat msg1 msg2 ) )
    }
    {}
    : s res ( nurl_cg_reg cg )
    : b isf | ( seq lt `double` ) ( seq lt `float` )
    : s ins ( binop_instr tt isf F )
    ( nurl_print `  ` ) ( nurl_print res ) ( nurl_print ` = ` )
    ( nurl_print ins ) ( nurl_print ` ` )
    ( nurl_print ( nurl_llty lt ) ) ( nurl_print ` ` )
    ( nurl_print lv ) ( nurl_print `, ` ) ( nurl_print rv ) ( nurl_print `\n` )
    // The RESULT value keeps the operands' signedness in its type, so it
    // survives into a downstream widen with no separate flag.
    ( nurl_set_last_type ? | ( ty_is_unsigned lt ) ( ty_is_unsigned rt )
    ( ty_to_unsigned lt ) lt )
    res
}

// ── Type-based dispatch for & and | ──────────────────────────────────
@ gen_logical_or_bitwise_and i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    // All operands of this n-ary `&` are values — forbid `^` across the
    // whole chain (lv here + the rest parsed by gen_logical_and /
    // gen_bitwise_binary). gen_stmt / control-flow arms reset the flag.
    = g_ret_forbidden 1
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
        {  // A string left operand with '@' as the NEXT token is an FFI
            // declaration written inside a function body — name the real
            // mistake instead of a boolean-AND type error.
            ? == ( nurl_lex_type lex ) TT_AT
            { ( die lex `FFI declaration inside a function body — an '&' library import ('& <lib> @ name args → ret') is a top-level form; move it to the top of the file next to the '$' imports` ) }
            {}
            : s msg ( nurl_str_cat `operator & requires matching types — got ` ( llvm_to_nurl lt ) )
            ( die lex ( nurl_str_cat msg ` and unknown` ) )
            ^ `error`
        }
    }
}

@ gen_logical_or_bitwise_or i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    // All operands of this n-ary `|` are values — see gen_logical_or_bitwise_and.
    = g_ret_forbidden 1
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
// either operand's TYPE is an unsigned scalar (`u8`/`u16`/`u32`/`u64`
// — signedness is in the type repr since A1). Equality predicates
// (`==`, `!=`) are sign-agnostic, so they take the signed entry. `add`/`sub`/`mul`/`and`/
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
    // Float `!=` must be UNORDERED-or-not-equal (`une`), not ordered (`one`):
    // IEEE 754 requires `x != y` to be TRUE when either operand is NaN, so the
    // canonical NaN check `!= x x` works. `une` matches C's `!=` and is
    // identical to `one` for non-NaN operands. (`==` stays `oeq` — NaN == NaN
    // is false, also matching C.)
    ? == tt TT_NE ? isf `fcmp une` `icmp ne`
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
        ( nurl_print ` = call ` ) ( nurl_print ( nurl_llty ret_type ) ) ( nurl_print ` ` ) ( nurl_print fn_ptr ) }
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
    : ~ i start_pos 0
    // Skip leading "{ " for closure struct types
    ? & >= len 2 == ( nurl_str_get fn_ptr_type 0 ) 123 { = start_pos 2 } {}

    : ~ b contains_space_paren F
    : ~ i i start_pos
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
        : ~ i space_idx start_pos
        : ~ i depth 0
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
// Signedness of narrow ints is in the argument's type (A1): a
// `u8`/`u16` arg zero-extends, `i8`/`i16` sign-extend — no
// side-channel, so a call result or arithmetic value promotes exactly
// like an ident load.

@ variadic_promoted_type s at → s {
    ? ( seq at `float` ) { ^ `double` } {}
    ? ( seq at `i1` ) { ^ `i32` } {}
    ? ( seq at `i8` ) { ^ `i32` } {}
    ? ( seq at `i16` ) { ^ `i32` } {}
    ? ( seq at `u8` ) { ^ `u32` } {}
    ? ( seq at `u16` ) { ^ `u32` } {}
    at
}

@ variadic_promote_arg i cg s at s av → s {
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
    ? | | | ( seq at `i8` ) ( seq at `i16` ) ( seq at `u8` ) ( seq at `u16` )
    { : s inst ? ( ty_is_unsigned at ) `zext` `sext`
        : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = ` ) ( nurl_print inst )
        ( nurl_print ` ` ) ( nurl_print ( nurl_llty at ) )
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
    : ~ s rest temps
    ~ != 0 ( nurl_str_len rest ) {
        : s reg ( str_first_word rest )
        = rest ( str_skip_word rest )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print reg ) ( nurl_print `)` ) ( emit_dbg_eol )
    }
}

// mem_propagate_call_ret_markers: publish the `__last_call_*` side-channels a
// caller reads about the value a just-emitted call returned — the callee's NURL
// return type (`??`/try propagation), Result Ok/Err payload LLVM types, `?T`
// inner type, owned-string/-slice ownership (Phase 2B auto-drop), returned
// owned struct-field list, borrow provenance, and return signedness — all keyed
// off the resolved callee name `cn` (`<cn>__nurl_ret`, `<cn>__ret_owned`, …).
//
// Factored out so EVERY dispatch path sets them identically. The impl-method
// dispatch path (Group F in gen_call) used to emit its call and return without
// any of these, so a trait method that returns an owned string leaked when its
// result was passed straight to another call (`( nurl_print ( label d ) )`), a
// borrow-returning trait method risked a double free, and a `u`- or `!T E`-
// returning one lost its signedness / try-propagation. One helper, one call per
// path, no path can silently omit a marker again.
@ mem_propagate_call_ret_markers i syms s cn → v {
    ( nurl_sym_def syms `__last_nurl_call__` ( nurl_sym_get syms ( nurl_str_cat cn `__nurl_ret` ) ) )
    ( nurl_sym_def syms `__last_call_res_t_llvm__` ( nurl_sym_get syms ( nurl_str_cat cn `__res_t_llvm` ) ) )
    ( nurl_sym_def syms `__last_call_res_e_llvm__` ( nurl_sym_get syms ( nurl_str_cat cn `__res_e_llvm` ) ) )
    ( nurl_sym_def syms `__last_call_opt_nurl_t__` ( nurl_sym_get syms ( nurl_str_cat cn `__opt_nurl_t` ) ) )
    ( nurl_sym_def syms `__last_call_ret_owned__` ( nurl_sym_get syms ( nurl_str_cat cn `__ret_owned` ) ) )
    ( nurl_sym_def syms `__last_call_ret_struct_fields__` ( nurl_sym_get syms ( nurl_str_cat cn `__ret_owned_fields` ) ) )
    ( nurl_sym_def syms `__last_value_borrow__`
    ? | != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat cn `__ret_borrow` ) ) )
    != 0 ( nurl_str_starts cn `vec_get` ) `1` `` )
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
    // Lint: `inout . obj field` reads obj's pointer directly (no gen_ident).
    ( lint_note_read obj )
    : s objptr ( nurl_sym_get syms ( nurl_str_cat obj `__ptr` ) )
    : s objty ( nurl_sym_get syms obj )
    ? == 0 ( nurl_str_len objptr )
    { ( die lex ( nurl_str_cat3
        `inout field argument: '` obj `' is not a struct binding in scope` ) ) }
    {}
    ? == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat obj `__mutable` ) ) )
    { ( die lex ( nurl_str_cat3
        `inout field argument: binding '` obj
        `' must be mutable ': ~' — the callee mutates its field in place` ) ) }
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
    ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty objty ) )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty objty ) ) ( nurl_print `* ` ) ( nurl_print objptr )
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
// Inlines the ASCII alpha/digit/underscore check. The nurlc compiler
// is self-contained (no `$`-imports) so the check lives here verbatim.
@ __is_ident_char i ch → b {
    ^ | | | & >= ch 65 <= ch 90 & >= ch 97 <= ch 122 & >= ch 48 <= ch 57 == ch 95
}

// Pure-NURL `nurl_str_*` helpers. Each is mirrored in
// `stdlib/core/string.nu` for user code; the duplication is because
// `nurlc.nu` has no `$`-imports — the linker sees only this local
// copy in the nurlc binary, only the stdlib copy in user binaries.

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

// nurl_lex_parse_int_wrap: parse a decimal integer literal's text into its
// two's-complement i64 bit pattern, accumulating with WRAPPING arithmetic.
// Unlike C `atoll` — which saturates at LLONG_MAX, silently clamping EVERY
// literal above i64 max (the entire upper half of the u64 range: e.g.
// `: u64 x 18446744073709551615` became i64 max 9223372036854775807 instead of
// all-ones) — this stores the exact bits, matching the hex/binary lexer paths
// which already accumulate with wrapping. Handles an optional leading '-';
// i64 MIN round-trips (its magnitude 2^63 wraps to i64 MIN, and negating that
// wraps back to itself). Input is already validated as `[-]?digit+` by the
// lexer, so non-digits are simply skipped.
@ nurl_lex_parse_int_wrap s sv → i {
    : i n ( nurl_str_len sv )
    : ~ i idx 0
    : ~ b neg F
    ? & > n 0 == ( nurl_str_get sv 0 ) 45 { = neg T = idx 1 } {}
    : ~ i acc 0
    ~ < idx n {
        : i c ( nurl_str_get sv idx )
        ? & >= c 48 <= c 57 { = acc + * acc 10 - c 48 } {}
        = idx + idx 1
    }
    ^ ? neg - 0 acc acc
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
    ? == & # i first 255 45 { = sign -1 = i 1 } {}
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
    : i32 rc ( access path # i32 0 )  // F_OK = 0
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

// ── codegen counters ──────────────────────────────────────────────
// Handle is a `nurl_zalloc`'d 16-byte block: slot 0 = next register
// number, slot 1 = next label number. The handle is opaque to all
// callers (passed back into _reg / _lbl / _reset / never deref'd
// directly); returned as `i` to preserve the original `: i cg ( … )`
// caller binding shape. Cast to `s` (== i8*) inside this file for
// `nurl_peek` / `nurl_poke` access.
//
// IMPORTANT — owned-string auto-detection: the @-fn bodies below
// deliberately return the `nurl_str_cat` result without an
// intervening `: s` binding. That keeps `__last_ident_name__` on an
// i64 binding (`n`) at fn exit, so the auto-detector at gen_fn_decl
// epilogue doesn't tag `nurl_cg_reg__ret_owned = "str"`. Callers
// (e.g. `gen_agg_lit`'s `= result r` chain) read the malloc'd
// register-name string as a borrow that lives for the rest of
// compilation — an intentional leak. Adding `: s tmp` here would
// flip the auto-tag and break gen_agg_lit's insertvalue chain (the
// binding would auto-drop before its register name is read in the
// next iteration).

@ nurl_cg_new → i {
    ^ # i ( nurl_zalloc 16 )
}

@ nurl_cg_reg i h → s {
    : s p # s h
    : i n ( nurl_peek p 0 )
    ( nurl_poke p 0 + n 1 )
    ^ ( nurl_str_cat `%r` ( nurl_str_int n ) )
}

@ nurl_cg_lbl i h s hint → s {
    : s p # s h
    : i n ( nurl_peek p 1 )
    ( nurl_poke p 1 + n 1 )
    ^ ( nurl_str_cat3 hint `_` ( nurl_str_int n ) )
}

@ nurl_cg_reset i h → v {
    : s p # s h
    ( nurl_poke p 0 0 )
    ( nurl_poke p 1 0 )
}

// ── "last type" sideband ──────────────────────────────────────────
// Module-level i8* held in `g_last_type_ptr` (stored as i64 — the
// `: i` slot can carry any pointer value). Initial 0 means "use the
// default `i64`". `nurl_set_last_type` strdup's the input and frees
// the previous value; `nurl_get_last_type` strdup's the current
// value so callers always receive an owned heap copy they can drop
// freely.

: ~ i g_last_type_ptr 0

@ nurl_get_last_type → s {
    ? == g_last_type_ptr 0 { ^ # s ( strdup `i64` ) } {}
    ^ # s ( strdup # s g_last_type_ptr )
}

// A value's SIGNEDNESS is a property of its type, and since A1 the type
// repr itself carries it: the channel stores the internal type (`u8` vs
// `i8` distinct), so signedness travels with every snapshot/restore of
// the last type automatically. There is no separate flag to set, clear,
// or forget — the former `__last_unsigned__` / `g_last_unsigned_p`
// side-channel (11 fuzzer-found miscompiles, then a coupling fix) is
// gone. Readers ask `ty_is_unsigned` of the type; IR emission lowers
// with `nurl_llty`.

@ nurl_set_last_type s t → v {
    : i old g_last_type_ptr
    = g_last_type_ptr # i ( strdup t )
    ? != old 0 { ( free # s old ) } {}
}

// ── symbol table ──────────────────────────────────────────────────
// Scoped flat-array map of (depth, name, type) entries. Handle is
// a `nurl_zalloc`'d 48-byte block, 6 i64 slots:
//   0: count          (number of valid entries)
//   1: depth          (current scope depth — incremented by _push)
//   2: cap            (current allocated capacity of each array)
//   3: names_buf  i8* (i8** array, length = cap; strdup'd names)
//   4: types_buf  i8* (i8** array, length = cap; strdup'd types)
//   5: depths_buf i8* (i64*  array, length = cap)
//
// Three parallel arrays (vs. one array-of-struct in the C version)
// give nurl_sym_get's hot linear scan better cache locality — the
// scan only fetches name pointers (8 B per entry, 8 entries per 64 B
// cache line), and only touches the types array on a match.
//
// Grow-by-2× starting at cap=64. nurl_sym_pop frees every (name,
// type) strdup at the current depth.
//
// nurl_sym_get returns a strdup'd copy of the matched type, or a
// strdup'd `""` on miss. The function is shaped to avoid the
// owned-string auto-tag (returns `^ # s (strdup ...)` with no
// intervening
// `: s tmp` binding holding an owned-string call result), preserving
// the same caller contract.

// IMPLEMENTATION NOTE — `*s` and `*i` pointer arithmetic (`. p k`
// and `= . p k v`) lowers to a single LLVM load/store, no function
// call. Every iteration of `nurl_sym_get` is a `strcmp` + a load +
// a compare + a branch — the same shape as the C version's
// `if (strcmp(entries[i].name, name) == 0)` loop. The earlier
// `nurl_peek`/`nurl_poke` pattern made the loop call a runtime
// function per slot, which LTO didn't fully inline; the wall-clock
// hit was ~1 s per stage2 compile of nurlc.nu itself.

// FNV-1a (32-bit) over the key, reduced into [0, nb). Used by the hashed
// symbol table below so lookup is O(1) amortised instead of O(table).
@ __sym_hash s name i nb → i {
    : i n ( nurl_str_len name )
    : ~ i hsh 2166136261
    : ~ i k 0
    ~ < k n {
        = hsh & ^^ hsh ( nurl_str_get name k ) 4294967295
        = hsh & * hsh 16777619 4294967295
        = k + k 1
    }
    ^ % hsh nb
}

@ __sym_grow i h → v {
    : s t # s h
    : i cap ( nurl_peek t 2 )
    : i newcap * cap 2
    : i count ( nurl_peek t 0 )
    : s names_old # s ( nurl_peek t 3 )
    : s types_old # s ( nurl_peek t 4 )
    : s depths_old # s ( nurl_peek t 5 )
    : s prev_old # s ( nurl_peek t 8 )
    : s names_new # s ( malloc * newcap 8 )
    : s types_new # s ( malloc * newcap 8 )
    : s depths_new # s ( malloc * newcap 8 )
    : s prev_new # s ( malloc * newcap 8 )
    : i nbytes * count 8
    ( memcpy names_new names_old nbytes )
    ( memcpy types_new types_old nbytes )
    ( memcpy depths_new depths_old nbytes )
    ( memcpy prev_new prev_old nbytes )
    ( free names_old )
    ( free types_old )
    ( free depths_old )
    ( free prev_old )
    ( nurl_poke t 2 newcap )
    ( nurl_poke t 3 # i names_new )
    ( nurl_poke t 4 # i types_new )
    ( nurl_poke t 5 # i depths_new )
    ( nurl_poke t 8 # i prev_new )
}

@ nurl_sym_new → i {
    // 9 slots: 0 count, 1 depth, 2 cap, 3 names, 4 types, 5 depths,
    // 6 nbuckets, 7 buckets (head index+1 per bucket; 0 = empty),
    // 8 prev (per-entry link to the previous entry in the same bucket).
    : i nb 4096
    : s t # s ( nurl_zalloc 72 )
    ( nurl_poke t 2 64 )
    ( nurl_poke t 3 # i # s ( malloc * 64 8 ) )
    ( nurl_poke t 4 # i # s ( malloc * 64 8 ) )
    ( nurl_poke t 5 # i # s ( malloc * 64 8 ) )
    ( nurl_poke t 6 nb )
    ( nurl_poke t 7 # i # s ( nurl_zalloc * nb 8 ) )
    ( nurl_poke t 8 # i # s ( malloc * 64 8 ) )
    ^ # i t
}

@ nurl_sym_def i h s name s type → v {
    : s t # s h
    : i count ( nurl_peek t 0 )
    : i cap ( nurl_peek t 2 )
    ? >= count cap { ( __sym_grow h ) } {}
    // Direct `*s` / `*i` array writes — one LLVM `store` each, no
    // runtime call. Read after the grow check so a realloc'd base
    // is picked up.
    : *s names # *s # s ( nurl_peek t 3 )
    : *s types # *s # s ( nurl_peek t 4 )
    : *i depths # *i # s ( nurl_peek t 5 )
    : *i buckets # *i # s ( nurl_peek t 7 )
    : *i prev # *i # s ( nurl_peek t 8 )
    : i bh ( __sym_hash name ( nurl_peek t 6 ) )
    = . names count # s ( strdup name )
    = . types count # s ( strdup type )
    = . depths count ( nurl_peek t 1 )
    // Push onto the front of the bucket chain — newest-first, so a
    // later definition of the same name shadows the earlier one, exactly
    // like the old backward linear scan.
    = . prev count . buckets bh
    = . buckets bh + count 1
    ( nurl_poke t 0 + count 1 )
}

@ nurl_sym_get i h s name → s {
    : s t # s h
    : i count ( nurl_peek t 0 )
    : *s names # *s # s ( nurl_peek t 3 )
    : *s types # *s # s ( nurl_peek t 4 )
    : *i buckets # *i # s ( nurl_peek t 7 )
    : *i prev # *i # s ( nurl_peek t 8 )
    : i bh ( __sym_hash name ( nurl_peek t 6 ) )
    // Walk this name's bucket chain newest-first. Entries are stored as
    // index+1 (0 = chain end); pop unlinks, so every chained index is < count.
    : ~ i cur . buckets bh
    ~ != cur 0 {
        : i idx - cur 1
        ? >= idx count { = cur 0 } {
            ? == 0 # i ( strcmp name . names idx )
            { ^ # s ( strdup . types idx ) }
            { = cur . prev idx }
        }
    }
    ^ # s ( strdup `` )
}

@ nurl_sym_push i h → v {
    : s t # s h
    ( nurl_poke t 1 + ( nurl_peek t 1 ) 1 )
}

@ nurl_sym_pop i h → v {
    : s t # s h
    : ~ i count ( nurl_peek t 0 )
    : i depth ( nurl_peek t 1 )
    : *s names # *s # s ( nurl_peek t 3 )
    : *s types # *s # s ( nurl_peek t 4 )
    : *i depths # *i # s ( nurl_peek t 5 )
    : *i buckets # *i # s ( nurl_peek t 7 )
    : *i prev # *i # s ( nurl_peek t 8 )
    : i nb ( nurl_peek t 6 )
    ~ & > count 0 == . depths - count 1 depth {
        : i idx - count 1
        // The top entry is the newest def for its name, hence the head of
        // its bucket chain — unlink it so the chain stays consistent.
        : i bh ( __sym_hash . names idx nb )
        = . buckets bh . prev idx
        ( free . names idx )
        ( free . types idx )
        = count - count 1
    }
    ( nurl_poke t 0 count )
    ? > depth 0 { ( nurl_poke t 1 - depth 1 ) } {}
}

// ── Did-you-mean suggestions (diagnostic cold path only) ──────────

// Flat-entry iteration over the symbol table, for the suggestion scan.
@ __sym_count i h → i {
    ^ ( nurl_peek # s h 0 )
}

// BORROW of the table's own strdup'd key copy — do not free.
@ __sym_entry_name i h i k → s {
    : *s names # *s # s ( nurl_peek # s h 3 )
    ^ . names k
}

// str[0..n) ends with `__arity` (no allocation).
@ __key_is_arity s str i n → b {
    ? < n 8 { ^ F } {}
    : *u p # *u str
    : s sfx `__arity`
    : *u q # *u sfx
    : ~ i k 0
    ~ < k 7 {
        ? != & # i . p + - n 7 k 255 & # i . q k 255 { ^ F } {}
        = k + k 1
    }
    ^ T
}

// str[0..n) contains a `__` pair (metadata-key marker; no allocation).
@ __key_has_dunder s str i n → b {
    : *u p # *u str
    : ~ i k 1
    ~ < k n {
        ? & == & # i . p - k 1 255 95 == & # i . p k 255 95 { ^ T } {}
        = k + k 1
    }
    ^ F
}

// Byte-equality of a[0..n) and b[0..n) (no allocation).
@ __bytes_eq s a s b i n → b {
    : *u p # *u a
    : *u q # *u b
    : ~ i k 0
    ~ < k n {
        ? != & # i . p k 255 & # i . q k 255 { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Levenshtein distance of a[0..la) / b[0..lb), early-out once every cell
// of a row exceeds `cap` (returns cap+1 then). Two u8 scratch rows of at
// least lb+1 bytes each are supplied by the caller so a scan over
// thousands of candidates doesn't allocate per pair.
@ __edit_dist_le s a i la s b i lb i cap * u r0v * u r1v → i {
    : ~ * u r0 r0v
    : ~ * u r1 r1v
    : *u pa # *u a
    : *u pb # *u b
    : ~ i j 0
    ~ <= j lb {
        = . r0 j # u j
        = j + j 1
    }
    : ~ i i 1
    : ~ i bail 0
    ~ & <= i la == bail 0 {
        = . r1 0 # u i
        : ~ i rowmin i
        : i ca & # i . pa - i 1 255
        : ~ i jj 1
        ~ <= jj lb {
            : i cb & # i . pb - jj 1 255
            : i cost ? == ca cb 0 1
            : ~ i d + & # i . r0 - jj 1 255 cost
            : i del + & # i . r0 jj 255 1
            : i ins + & # i . r1 - jj 1 255 1
            ? < del d { = d del } {}
            ? < ins d { = d ins } {}
            ? > d 250 { = d 250 } {}
            = . r1 jj # u d
            ? < d rowmin { = rowmin d } {}
            = jj + jj 1
        }
        ? > rowmin cap { = bail 1 } {}
        : *u tmp r0
        = r0 r1
        = r1 tmp
        = i + i 1
    }
    ? != bail 0 { ^ + cap 1 } {}
    ^ & # i . r0 lb 255
}

// Closest known name to `name`, or `` when nothing is close enough.
// Candidates come from the symbol table itself: every `<fn>__arity` key
// (scan_fn_sigs pre-registers every @-function program-wide) plus every
// plain no-`__` key (builtins, FFI, bindings, constants). Distance cap 1
// for names up to 4 chars, else 2 — rustc-style. Returns an OWNED string
// (the caller feeds it straight into a die message).
@ __suggest_ident i syms s name → s {
    : i n ( nurl_str_len name )
    ? < n 2 { ^ ( strdup `` ) } {}
    : i cap ? <= n 4 1 2
    : i cnt ( __sym_count syms )
    : *u row0 # *u ( malloc 160 )
    : *u row1 # *u ( malloc 160 )
    : ~ i best_k -1
    : ~ i best_len 0
    : ~ i bestd + cap 1
    : ~ i k 0
    ~ < k cnt {
        : s key ( __sym_entry_name syms k )
        : i kl ( nurl_str_len key )
        : ~ i cl 0
        ? ( __key_is_arity key kl )
        { = cl - kl 7 }
        { ? ! ( __key_has_dunder key kl ) { = cl kl } {} }
        // Prune: viable length, not the name itself (an exact key match
        // reaching a diagnostic means a different-namespace hit — a
        // same-name suggestion would read as nonsense).
        : i diff ? > cl n - cl n - n cl
        ? & & & > cl 1 < cl 150 <= diff cap ! & == cl n ( __bytes_eq key name n )
        {
            : i d ( __edit_dist_le name n key cl cap row0 row1 )
            ? < d bestd {
                = bestd d
                = best_k k
                = best_len cl
            } {}
        } {}
        = k + k 1
    }
    ( nurl_free # s row0 )
    ( nurl_free # s row1 )
    ? >= best_k 0
    { ^ ( nurl_str_slice ( __sym_entry_name syms best_k ) 0 best_len ) }
    {}
    ^ ( strdup `` )
}

// ══════════════════════════════════════════════════════════════════
// ── Lexer ────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════
//
// Pure-NURL lexer. Handle is a `nurl_zalloc`'d
// 280-byte heap block, 35 i64 slots. Layout (slot offsets):
//
//   0:  src       (i8*)         — strdup'd source bytes
//   1:  filename  (i8*)         — strdup'd filename
//   2:  pos       (i64)         — current byte position
//   3:  len       (i64)         — strlen(src) cached at _new
//   4:  line      (i64)         — current 1-based line number
//   5-10:  cur token            — always valid after _new primes it
//   11-16: peek token  + valid  — lookahead 1
//   17-22: peek2 token + valid  — lookahead 2
//   23-28: peek3 token + valid  — lookahead 3
//   29-34: peek4 token + valid  — lookahead 4
//
// Token field offsets (relative to token base):
//   0: type  1: val (i8*)  2: inum  3: line  4: start  5: valid
//
// `fnum` is NOT stored (the C version's field was dead — every parser
// callsite reads `nurl_lex_val` and emits the string form into the
// LLVM IR directly, never going through `nurl_lex_fnum`). Saves a slot
// per token + removes the float-bitcast bridge.
//
// The token `val` field is a `strdup`'d copy owned by the lexer; the
// lexer overwrites/leaks it on advance — same lifetime contract as
// the C version, which never freed token vals either.
//
// `nurl_lex_val` returns a fresh `strdup` of the current token's val
// so callers can stash a stable copy across `nurl_lex_advance` calls.
// Same contract as runtime.c.

: i LX_SRC 0
: i LX_FILENAME 1
: i LX_POS 2
: i LX_LEN 3
: i LX_LINE 4
: i LX_CUR 5
: i LX_PEEK 11
: i LX_PEEK2 17
: i LX_PEEK3 23
: i LX_PEEK4 29

: i TF_TYPE 0
: i TF_VAL 1
: i TF_INUM 2
: i TF_LINE 3
: i TF_START 4
: i TF_VALID 5

: i LX_SIZE 280  // 35 slots × 8 bytes

// ── ASCII byte-class predicates ──────────────────────────────────

@ __lx_is_digit i c → b {
    ^ & >= c 48 <= c 57
}

// Hex-digit predicate + value, for `0x…` integer literals.
@ __lx_is_hex_digit i c → b {
    ? ( __lx_is_digit c ) { ^ T } {}
    ? & >= c 97 <= c 102 { ^ T } {}  // a-f
    ? & >= c 65 <= c 70 { ^ T } {}  // A-F
    ^ F
}

@ __lx_hex_val i c → i {
    ? ( __lx_is_digit c ) { ^ - c 48 } {}
    ? & >= c 97 <= c 102 { ^ + 10 - c 97 } {}  // a-f
    ^ + 10 - c 65  // A-F
}

// Binary-digit predicate, for `0b…` integer literals.
@ __lx_is_bin_digit i c → b {
    ^ | == c 48 == c 49
}

@ __lx_is_alpha i c → b {
    ^ | & >= c 65 <= c 90 & >= c 97 <= c 122
}

@ __lx_is_alpha_us i c → b {
    ^ | ( __lx_is_alpha c ) == c 95
}

@ __lx_is_ident_cont i c → b {
    ^ | ( __lx_is_alpha_us c ) ( __lx_is_digit c )
}

@ __lx_is_space i c → b {
    ^ | | | == c 32 == c 9 == c 10 == c 13
}

// ── Token-slot helpers ───────────────────────────────────────────

// Write a complete token into slot at `base`. `val` is taken
// ownership of (caller must pass an i8* the lexer can hold; usually
// from strdup or an inline malloc). Marks the slot valid.
@ __tok_write i lex i base i type s val i inum i line i start → v {
    : s p # s lex
    ( nurl_poke p + base TF_TYPE type )
    ( nurl_poke p + base TF_VAL # i val )
    ( nurl_poke p + base TF_INUM inum )
    ( nurl_poke p + base TF_LINE line )
    ( nurl_poke p + base TF_START start )
    ( nurl_poke p + base TF_VALID 1 )
}

// Copy a token from src_base into dst_base within the same lexer.
// Both must be valid token-slot bases.
@ __tok_shift i lex i src_base i dst_base → v {
    : s p # s lex
    ( nurl_poke p + dst_base TF_TYPE ( nurl_peek p + src_base TF_TYPE ) )
    ( nurl_poke p + dst_base TF_VAL ( nurl_peek p + src_base TF_VAL ) )
    ( nurl_poke p + dst_base TF_INUM ( nurl_peek p + src_base TF_INUM ) )
    ( nurl_poke p + dst_base TF_LINE ( nurl_peek p + src_base TF_LINE ) )
    ( nurl_poke p + dst_base TF_START ( nurl_peek p + src_base TF_START ) )
    ( nurl_poke p + dst_base TF_VALID 1 )
}

// ── Whitespace + comment skip ────────────────────────────────────

@ __lx_skip_ws i lex → v {
    : s p # s lex
    : *u src # *u # s ( nurl_peek p LX_SRC )
    : i len ( nurl_peek p LX_LEN )
    : ~ i pos ( nurl_peek p LX_POS )
    : ~ i line ( nurl_peek p LX_LINE )
    : ~ b done F
    ~ ! done {
        : ~ b ws_done F
        ~ ! ws_done {
            ? >= pos len { = ws_done T } {
                : i c & # i . src pos 255
                ? ( __lx_is_space c ) {
                    ? == c 10 { = line + line 1 } {}
                    = pos + pos 1
                } { = ws_done T }
            }
        }
        ? & & < + pos 1 len
        == & # i . src pos 255 47
        == & # i . src + pos 1 255 47 {
            // line comment — skip to end of line (exclusive of '\n').
            ~ & < pos len != & # i . src pos 255 10 { = pos + pos 1 }
        } { = done T }
    }
    ( nurl_poke p LX_POS pos )
    ( nurl_poke p LX_LINE line )
}

// ── Lex one token, write into slot at `base`.
// Reads from current lexer pos; advances pos to point past the token.
// Updates line if the token consumed a newline (only backtick strings
// can do that). Always produces a token (TT_EOF at end of input).

@ __lex_one i lex i base → v {
    ( __lx_skip_ws lex )
    : s p # s lex
    : *u src # *u # s ( nurl_peek p LX_SRC )
    : i len ( nurl_peek p LX_LEN )
    : ~ i pos ( nurl_peek p LX_POS )
    : ~ i line ( nurl_peek p LX_LINE )
    : i start pos
    : ~ b done F

    // ── EOF ──
    ? >= pos len {
        ( __tok_write lex base TT_EOF ( strdup `` ) 0 line start )
        = done T
    } {}

    // ── UTF-8 arrow → (E2 86 92) ──
    ? ! done {
        ? & & & < + pos 2 len
        == & # i . src pos 255 226
        == & # i . src + pos 1 255 134
        == & # i . src + pos 2 255 146 {
            = pos + pos 3
            ( __tok_write lex base TT_ARROW ( strdup `→` ) 0 line start )
            = done T
        } {}
    } {}

    // ── Backtick string with \n \t \r \\ escape handling ──
    //
    // IMPORTANT: only the four sequences `\n` `\t` `\r` `\\` are
    // recognised as escapes. Any other `\X` (including `\``) writes
    // the lone `\` to the output and ADVANCES BY ONE byte — so a
    // backtick following a backslash terminates the string in the
    // normal way. This matches the historic C lexer's behaviour
    // verbatim; treating `\\`` as an escape (the obvious-looking
    // bug) breaks comment skipping for any line with backticked
    // content because the string then consumes the rest of the
    // file. The two loops below (scan-for-end + fill) must both use
    // the same is-real-escape predicate.
    //
    // Escapes only shrink output, so the byte span between the
    // backticks (+1 for NUL) is always a sufficient allocation.
    ? ! done {
        ? == & # i . src pos 255 96 {
            : i str_open + pos 1
            : ~ i scan str_open
            : ~ i scan_line line
            ~ & < scan len != & # i . src scan 255 96 {
                ? == & # i . src scan 255 10 { = scan_line + scan_line 1 } {}
                ? & == & # i . src scan 255 92 < + scan 1 len {
                    : i nx & # i . src + scan 1 255
                    ? | | | == nx 110 == nx 116 == nx 114 == nx 92 {
                        = scan + scan 2
                    } {
                        = scan + scan 1
                    }
                } {
                    = scan + scan 1
                }
            }
            : i raw_len - scan str_open
            : s buf # s ( malloc + raw_len 1 )
            : *u bp # *u buf
            : ~ i blen 0
            : ~ i rp str_open
            ~ < rp scan {
                : i ch & # i . src rp 255
                ? & == ch 92 < + rp 1 scan {
                    : i nx & # i . src + rp 1 255
                    ? == nx 110 {
                        = . bp blen # u 10 = blen + blen 1 = rp + rp 2
                    } {
                        ? == nx 116 {
                            = . bp blen # u 9 = blen + blen 1 = rp + rp 2
                        } {
                            ? == nx 114 {
                                = . bp blen # u 13 = blen + blen 1 = rp + rp 2
                            } {
                                ? == nx 92 {
                                    = . bp blen # u 92 = blen + blen 1 = rp + rp 2
                                } {
                                    // unknown \X — write the lone `\`
                                    // and advance 1 byte; the next
                                    // iteration handles X normally.
                                    = . bp blen # u ch
                                    = blen + blen 1
                                    = rp + rp 1
                                }
                            }
                        }
                    }
                } {
                    = . bp blen # u ch = blen + blen 1 = rp + rp 1
                }
            }
            = . bp blen # u 0
            = line scan_line
            = pos ? < scan len + scan 1 scan  // skip closing ` if present
            ( __tok_write lex base TT_STR buf 0 line start )
            = done T
        } {}
    } {}

    // ── Negative integer / float literal: '-' immediately followed
    //    by a digit. The unary-minus binary operator is written with
    //    whitespace (`- a b`); a tight `-5` is a single token.
    ? ! done {
        ? & == & # i . src pos 255 45
        & < + pos 1 len
        ( __lx_is_digit & # i . src + pos 1 255 ) {
            : i lit_start pos
            = pos + pos 1  // consume '-'
            ~ & < pos len ( __lx_is_digit & # i . src pos 255 ) { = pos + pos 1 }
            : ~ b is_float F
            ? & & < + pos 1 len
            == & # i . src pos 255 46
            ( __lx_is_digit & # i . src + pos 1 255 ) {
                = is_float T
                = pos + pos 1
                ~ & < pos len ( __lx_is_digit & # i . src pos 255 ) { = pos + pos 1 }
                ? & < pos len
                | == & # i . src pos 255 101
                == & # i . src pos 255 69 {
                    = pos + pos 1
                    ? & < pos len
                    | == & # i . src pos 255 43
                    == & # i . src pos 255 45 {
                        = pos + pos 1
                    } {}
                    ~ & < pos len ( __lx_is_digit & # i . src pos 255 ) { = pos + pos 1 }
                } {}
            } {}
            // Materialise the literal text as an owned string.
            : i n - pos lit_start
            : s sv # s ( malloc + n 1 )
            ( memcpy sv # s + # i # *u # s ( nurl_peek p LX_SRC ) lit_start n )
            : *u svp # *u sv
            = . svp n # u 0
            ? is_float {
                ( __tok_write lex base TT_FLOAT sv 0 line start )
            } {
                ( __tok_write lex base TT_INT sv ( nurl_lex_parse_int_wrap sv ) line start )
            }
            = done T
        } {}
    } {}

    // ── Hex / binary integer literal: 0x… / 0b… ──
    // Checked before the decimal path so `0x…` / `0b…` don't lex as a
    // bare `0` followed by an identifier. The token's inum carries the
    // parsed value; sv keeps the original spelling for diagnostics.
    ? & ! done & == & # i . src pos 255 48 < + pos 1 len {
        : i c1 & # i . src + pos 1 255
        ? | == c1 120 == c1 88 {  // 'x' / 'X'
            : i lit0 pos
            = pos + pos 2
            : ~ i hacc 0
            : i hdig0 pos
            ~ & < pos len ( __lx_is_hex_digit & # i . src pos 255 ) {
                = hacc + * hacc 16 ( __lx_hex_val & # i . src pos 255 )
                = pos + pos 1
            }
            ? == pos hdig0 { ( die lex `malformed hex literal: expected hex digit after '0x'` ) } {}
            : i hn - pos lit0
            : s hsv # s ( malloc + hn 1 )
            ( memcpy hsv # s + # i # *u # s ( nurl_peek p LX_SRC ) lit0 hn )
            : *u hsvp # *u hsv
            = . hsvp hn # u 0
            ( __tok_write lex base TT_INT hsv hacc line start )
            = done T
        } {}
        ? & ! done | == c1 98 == c1 66 {  // 'b' / 'B'
            : i lit0 pos
            = pos + pos 2
            : ~ i bacc 0
            : i bdig0 pos
            ~ & < pos len ( __lx_is_bin_digit & # i . src pos 255 ) {
                = bacc + * bacc 2 - & # i . src pos 255 48
                = pos + pos 1
            }
            ? == pos bdig0 { ( die lex `malformed binary literal: expected 0/1 after '0b'` ) } {}
            : i bn - pos lit0
            : s bsv # s ( malloc + bn 1 )
            ( memcpy bsv # s + # i # *u # s ( nurl_peek p LX_SRC ) lit0 bn )
            : *u bsvp # *u bsv
            = . bsvp bn # u 0
            ( __tok_write lex base TT_INT bsv bacc line start )
            = done T
        } {}
    } {}

    // ── Plain integer or float literal ──
    ? ! done {
        ? ( __lx_is_digit & # i . src pos 255 ) {
            : i lit_start pos
            ~ & < pos len ( __lx_is_digit & # i . src pos 255 ) { = pos + pos 1 }
            : ~ b is_float F
            ? & & < + pos 1 len
            == & # i . src pos 255 46
            ( __lx_is_digit & # i . src + pos 1 255 ) {
                = is_float T
                = pos + pos 1
                ~ & < pos len ( __lx_is_digit & # i . src pos 255 ) { = pos + pos 1 }
                ? & < pos len
                | == & # i . src pos 255 101
                == & # i . src pos 255 69 {
                    = pos + pos 1
                    ? & < pos len
                    | == & # i . src pos 255 43
                    == & # i . src pos 255 45 {
                        = pos + pos 1
                    } {}
                    ~ & < pos len ( __lx_is_digit & # i . src pos 255 ) { = pos + pos 1 }
                } {}
            } {}
            : i n - pos lit_start
            : s sv # s ( malloc + n 1 )
            ( memcpy sv # s + # i # *u # s ( nurl_peek p LX_SRC ) lit_start n )
            : *u svp # *u sv
            = . svp n # u 0
            ? is_float {
                ( __tok_write lex base TT_FLOAT sv 0 line start )
            } {
                ( __tok_write lex base TT_INT sv ( nurl_lex_parse_int_wrap sv ) line start )
            }
            = done T
        } {}
    } {}

    // ── Identifier / keyword ──
    ? ! done {
        ? ( __lx_is_alpha_us & # i . src pos 255 ) {
            : i id_start pos
            ~ & < pos len ( __lx_is_ident_cont & # i . src pos 255 ) { = pos + pos 1 }
            // Namespace `::` merge — a::b[::c...] becomes a__b[__c...].
            // Each `::` is exactly two ASCII bytes followed by an
            // ident-start char (alpha or _).
            ~ & & < + pos 2 len
            & == & # i . src pos 255 58
            == & # i . src + pos 1 255 58
            ( __lx_is_alpha_us & # i . src + pos 2 255 ) {
                = pos + pos 2
                ~ & < pos len ( __lx_is_ident_cont & # i . src pos 255 ) { = pos + pos 1 }
            }
            // Materialise the identifier text.
            : i n - pos id_start
            : s id # s ( malloc + n 1 )
            ( memcpy id # s + # i # *u # s ( nurl_peek p LX_SRC ) id_start n )
            : *u idp # *u id
            // Rewrite any `::` (two colons) found in `id` to `__`.
            : ~ i k 0
            ~ < k n {
                ? & == & # i . idp k 255 58
                & < + k 1 n
                == & # i . idp + k 1 255 58 {
                    = . idp k # u 95
                    = . idp + k 1 # u 95
                    = k + k 2
                } {
                    = k + k 1
                }
            }
            = . idp n # u 0
            : ~ i ttype TT_IDENT
            : ~ i inum 0
            // Bool literals, sizeof, pub, base type kws (`i u f b s v`),
            // and fixed-width int/float kws (i8/i16/i32/i64/u16/u32/u64/f32).
            ? == n 1 {
                : i c0 & # i . idp 0 255
                ? == c0 84 { = ttype TT_BOOL = inum 1 } {}  // 'T'
                ? == c0 70 { = ttype TT_BOOL = inum 0 } {}  // 'F'
                ? == c0 90 { = ttype TT_SIZEOF } {}  // 'Z'
                ? | | | | | == c0 105 == c0 117 == c0 102 == c0 98 == c0 115 == c0 118 {
                    = ttype TT_TYPE_KW
                } {}
            } {}
            ? & == ttype TT_IDENT == n 3 {
                ? & == & # i . idp 0 255 112
                & == & # i . idp 1 255 117
                == & # i . idp 2 255 98 {
                    = ttype TT_PUB
                } {}
            } {}
            ? & == ttype TT_IDENT | | == n 2 == n 3 == n 4 {
                // i8 i16 i32 i64 u16 u32 u64 f32
                : i c0 & # i . idp 0 255
                ? | | == c0 105 == c0 117 == c0 102 {
                    ? == n 2 {
                        : i c1 & # i . idp 1 255
                        ? == c1 56 { = ttype TT_TYPE_KW } {}  // 'i8'
                    } {}
                    ? == n 3 {
                        : i c1 & # i . idp 1 255
                        : i c2 & # i . idp 2 255
                        ? & == c1 49 == c2 54 { = ttype TT_TYPE_KW } {}  // ?16
                        ? & == c1 51 == c2 50 { = ttype TT_TYPE_KW } {}  // ?32
                        ? & == c1 54 == c2 52 { = ttype TT_TYPE_KW } {}  // ?64
                    } {}
                } {}
            } {}
            ( __tok_write lex base ttype id inum line start )
            = done T
        } {}
    } {}

    // ── Three-char `...` ellipsis ──
    ? ! done {
        ? & & < + pos 2 len
        == & # i . src pos 255 46
        & == & # i . src + pos 1 255 46
        == & # i . src + pos 2 255 46 {
            = pos + pos 3
            ( __tok_write lex base TT_ELLIPSIS ( strdup `...` ) 0 line start )
            = done T
        } {}
    } {}

    // ── Two-char operators ──
    ? ! done {
        ? < + pos 1 len {
            : i c1 & # i . src pos 255
            : i c2 & # i . src + pos 1 255
            ? & == c1 61 == c2 61 { = pos + pos 2 ( __tok_write lex base TT_EQEQ ( strdup `==` ) 0 line start ) = done T } {}
            ? & ! done & == c1 33 == c2 61 { = pos + pos 2 ( __tok_write lex base TT_NE ( strdup `!=` ) 0 line start ) = done T } {}
            ? & ! done & == c1 60 == c2 61 { = pos + pos 2 ( __tok_write lex base TT_LE ( strdup `<=` ) 0 line start ) = done T } {}
            ? & ! done & == c1 62 == c2 61 { = pos + pos 2 ( __tok_write lex base TT_GE ( strdup `>=` ) 0 line start ) = done T } {}
            ? & ! done & == c1 60 == c2 60 { = pos + pos 2 ( __tok_write lex base TT_SHL ( strdup `<<` ) 0 line start ) = done T } {}
            ? & ! done & == c1 62 == c2 62 { = pos + pos 2 ( __tok_write lex base TT_SHR ( strdup `>>` ) 0 line start ) = done T } {}
            ? & ! done & == c1 63 == c2 63 { = pos + pos 2 ( __tok_write lex base TT_QUESTQUEST ( strdup `??` ) 0 line start ) = done T } {}
            ? & ! done & == c1 94 == c2 94 { = pos + pos 2 ( __tok_write lex base TT_CARETCARET ( strdup `^^` ) 0 line start ) = done T } {}
            ? & ! done & == c1 124 == c2 124 { = pos + pos 2 ( __tok_write lex base TT_OROR ( strdup `||` ) 0 line start ) = done T } {}
            ? & ! done & == c1 38 == c2 38 { = pos + pos 2 ( __tok_write lex base TT_ANDAND ( strdup `&&` ) 0 line start ) = done T } {}
        } {}
    } {}

    // ── Single-char operators (fallback) ──
    ? ! done {
        : i c & # i . src pos 255
        = pos + pos 1
        ? == c 64 { ( __tok_write lex base TT_AT ( strdup `@` ) 0 line start ) = done T } {}
        ? & ! done == c 58 { ( __tok_write lex base TT_COLON ( strdup `:` ) 0 line start ) = done T } {}
        ? & ! done == c 61 { ( __tok_write lex base TT_EQ ( strdup `=` ) 0 line start ) = done T } {}
        ? & ! done == c 94 { ( __tok_write lex base TT_CARET ( strdup `^` ) 0 line start ) = done T } {}
        ? & ! done == c 63 { ( __tok_write lex base TT_QUEST ( strdup `?` ) 0 line start ) = done T } {}
        ? & ! done == c 126 { ( __tok_write lex base TT_TILDE ( strdup `~` ) 0 line start ) = done T } {}
        ? & ! done == c 40 { ( __tok_write lex base TT_LPAREN ( strdup `(` ) 0 line start ) = done T } {}
        ? & ! done == c 41 { ( __tok_write lex base TT_RPAREN ( strdup `)` ) 0 line start ) = done T } {}
        ? & ! done == c 123 { ( __tok_write lex base TT_LBRACE ( strdup `{` ) 0 line start ) = done T } {}
        ? & ! done == c 125 { ( __tok_write lex base TT_RBRACE ( strdup `}` ) 0 line start ) = done T } {}
        ? & ! done == c 46 { ( __tok_write lex base TT_DOT ( strdup `.` ) 0 line start ) = done T } {}
        ? & ! done == c 35 { ( __tok_write lex base TT_HASH ( strdup `#` ) 0 line start ) = done T } {}
        ? & ! done == c 33 { ( __tok_write lex base TT_BANG ( strdup `!` ) 0 line start ) = done T } {}
        ? & ! done == c 43 { ( __tok_write lex base TT_PLUS ( strdup `+` ) 0 line start ) = done T } {}
        ? & ! done == c 45 { ( __tok_write lex base TT_MINUS ( strdup `-` ) 0 line start ) = done T } {}
        ? & ! done == c 42 { ( __tok_write lex base TT_STAR ( strdup `*` ) 0 line start ) = done T } {}
        ? & ! done == c 47 { ( __tok_write lex base TT_SLASH ( strdup `/` ) 0 line start ) = done T } {}
        ? & ! done == c 37 { ( __tok_write lex base TT_PERCENT ( strdup `%` ) 0 line start ) = done T } {}
        ? & ! done == c 38 { ( __tok_write lex base TT_AMP ( strdup `&` ) 0 line start ) = done T } {}
        ? & ! done == c 124 { ( __tok_write lex base TT_PIPE ( strdup `|` ) 0 line start ) = done T } {}
        ? & ! done == c 60 { ( __tok_write lex base TT_LT ( strdup `<` ) 0 line start ) = done T } {}
        ? & ! done == c 62 { ( __tok_write lex base TT_GT ( strdup `>` ) 0 line start ) = done T } {}
        ? & ! done == c 91 { ( __tok_write lex base TT_LBRACK ( strdup `[` ) 0 line start ) = done T } {}
        ? & ! done == c 93 { ( __tok_write lex base TT_RBRACK ( strdup `]` ) 0 line start ) = done T } {}
        ? & ! done == c 59 { ( __tok_write lex base TT_SEMICOL ( strdup `;` ) 0 line start ) = done T } {}
        ? & ! done == c 92 { ( __tok_write lex base TT_BACKSLASH ( strdup `\\` ) 0 line start ) = done T } {}
        ? & ! done == c 36 { ( __tok_write lex base TT_DOLLAR ( strdup `$` ) 0 line start ) = done T } {}
        // Unknown byte — emit IDENT "?XX" so caller can diagnose.
        ? ! done {
            : s buf # s ( malloc 4 )
            : *u bp # *u buf
            = . bp 0 # u 63  // '?'
            : i hi / c 16
            : i lo & c 15
            = . bp 1 # u + ? < hi 10 + 48 hi + 55 hi 0
            = . bp 2 # u + ? < lo 10 + 48 lo + 55 lo 0
            = . bp 3 # u 0
            ( __tok_write lex base TT_IDENT buf 0 line start )
            = done T
        } {}
    } {}

    ( nurl_poke p LX_POS pos )
    ( nurl_poke p LX_LINE line )
}

// ── Public API ───────────────────────────────────────────────────

@ nurl_lex_new s src s filename → i {
    : s lx # s ( nurl_zalloc LX_SIZE )
    ( nurl_poke lx LX_SRC # i ( strdup src ) )
    ( nurl_poke lx LX_FILENAME # i ( strdup filename ) )
    ( nurl_poke lx LX_POS 0 )
    ( nurl_poke lx LX_LEN ( strlen src ) )
    ( nurl_poke lx LX_LINE 1 )
    // Prime cur token.
    ( __lex_one # i lx LX_CUR )
    ^ # i lx
}

@ nurl_lex_type i h → i {
    : s p # s h
    ^ ( nurl_peek p + LX_CUR TF_TYPE )
}

@ nurl_lex_val i h → s {
    : s p # s h
    ^ # s ( strdup # s ( nurl_peek p + LX_CUR TF_VAL ) )
}

@ nurl_lex_inum i h → i {
    : s p # s h
    ^ ( nurl_peek p + LX_CUR TF_INUM )
}

// fnum: re-parse the val on demand. nurl_lex_fnum has no caller in
// the compiler or stdlib today (the float-literal codepath emits the
// val string directly into the LLVM IR), but the symbol stays for
// backward-compat with any external code that may declare it.
@ nurl_lex_fnum i h → f {
    : s p # s h
    : s v # s ( nurl_peek p + LX_CUR TF_VAL )
    ^ ( atof v )
}

@ nurl_lex_line i h → i {
    : s p # s h
    ^ ( nurl_peek p + LX_CUR TF_LINE )
}

@ nurl_lex_filename i h → s {
    : s p # s h
    ^ # s ( strdup # s ( nurl_peek p LX_FILENAME ) )
}

@ nurl_lex_cur_start i h → i {
    : s p # s h
    ^ ( nurl_peek p + LX_CUR TF_START )
}

// Walk back from cur.start_pos to the previous '\n' (or BOF) counting
// bytes. UTF-8 multibyte chars bump the column by their byte count;
// editors that measure post-newline bytes still land on the right
// line:col since both they and the lexer count bytes.
@ nurl_lex_col i h → i {
    : s p # s h
    : *u src # *u # s ( nurl_peek p LX_SRC )
    : i len ( nurl_peek p LX_LEN )
    : ~ i pos ( nurl_peek p + LX_CUR TF_START )
    ? < pos 0 { = pos 0 } {}
    ? > pos len { = pos len } {}
    : ~ i col 1
    ~ & > pos 0 != & # i . src - pos 1 255 10 { = pos - pos 1 = col + col 1 }
    ^ col
}

// Return the source text of the line containing the current token,
// with tabs expanded to single spaces so caller-rendered caret
// pointers line up. Heap-allocated; caller does not free (process
// is about to exit).
@ nurl_lex_line_text i h → s {
    : s p # s h
    : *u src # *u # s ( nurl_peek p LX_SRC )
    : i len ( nurl_peek p LX_LEN )
    : ~ i base ( nurl_peek p + LX_CUR TF_START )
    ? < base 0 { = base 0 } {}
    ? > base len { = base len } {}
    : ~ i line_start base
    ~ & > line_start 0 != & # i . src - line_start 1 255 10 { = line_start - line_start 1 }
    : ~ i line_end base
    ~ & < line_end len != & # i . src line_end 255 10 { = line_end + line_end 1 }
    ? & > line_end line_start == & # i . src - line_end 1 255 13 { = line_end - line_end 1 } {}
    : i n - line_end line_start
    : s out # s ( malloc + n 1 )
    : *u op # *u out
    : ~ i i 0
    ~ < i n {
        : i c & # i . src + line_start i 255
        = . op i # u ? == c 9 32 c
        = i + i 1
    }
    = . op n # u 0
    ^ out
}

// Build a `pad` space + '^' caret pointer for diagnostics.
@ nurl_diag_caret i col → s {
    : ~ i pad ? > col 0 - col 1 0
    ? > pad 4096 { = pad 4096 } {}
    : s out # s ( malloc + pad 2 )
    : *u op # *u out
    : ~ i i 0
    ~ < i pad { = . op i # u 32 = i + i 1 }
    = . op pad # u 94
    = . op + pad 1 # u 0
    ^ out
}

// Text of 1-based line `line` in the raw buffer src[0..len), tabs
// rendered as spaces (mirrors nurl_lex_line_text) — for diagnostics
// anchored somewhere other than the lexer's current token. OWNED
// return; empty string when the line is out of range.
@ __src_line_text s src i len i line → s {
    : *u sp # *u src
    : ~ i k 0
    : ~ i ln 1
    ~ & < k len < ln line {
        ? == & # i . sp k 255 10 { = ln + ln 1 } {}
        = k + k 1
    }
    ? < ln line { ^ ( strdup `` ) } {}
    : i line_start k
    : ~ i line_end k
    ~ & < line_end len != & # i . sp line_end 255 10 { = line_end + line_end 1 }
    ? & > line_end line_start == & # i . sp - line_end 1 255 13 { = line_end - line_end 1 } {}
    : i n - line_end line_start
    : s out # s ( malloc + n 1 )
    : *u op # *u out
    : ~ i i 0
    ~ < i n {
        : i c & # i . sp + line_start i 255
        = . op i # u ? == c 9 32 c
        = i + i 1
    }
    = . op n # u 0
    ^ out
}

// __src_line_text over the lexer's own source buffer.
@ nurl_lex_line_text_at i h i line → s {
    : s p # s h
    ^ ( __src_line_text # s ( nurl_peek p LX_SRC ) ( nurl_peek p LX_LEN ) line )
}

@ nurl_lex_src_slice i h i start i n → s {
    : s p # s h
    : i len ( nurl_peek p LX_LEN )
    : ~ i st start
    : ~ i k n
    ? < st 0 { = st 0 } {}
    ? > st len { = st len } {}
    : i avail - len st
    ? < k 0 { = k 0 } {}
    ? > k avail { = k avail } {}
    : s out # s ( malloc + k 1 )
    ( memcpy out # s + # i # *u # s ( nurl_peek p LX_SRC ) st k )
    : *u op # *u out
    = . op k # u 0
    ^ out
}

@ nurl_lex_set_pos i h i new_pos → v {
    : s p # s h
    : *u src # *u # s ( nurl_peek p LX_SRC )
    : i len ( nurl_peek p LX_LEN )
    : ~ i np new_pos
    ? < np 0 { = np 0 } {}
    ? > np len { = np len } {}
    // Invalidate lookahead.
    ( nurl_poke p + LX_PEEK TF_VALID 0 )
    ( nurl_poke p + LX_PEEK2 TF_VALID 0 )
    ( nurl_poke p + LX_PEEK3 TF_VALID 0 )
    ( nurl_poke p + LX_PEEK4 TF_VALID 0 )
    // Recompute line by scanning from start of src.
    : ~ i line 1
    : ~ i i 0
    ~ & < i np < i len {
        ? == & # i . src i 255 10 { = line + line 1 } {}
        = i + i 1
    }
    ( nurl_poke p LX_POS np )
    ( nurl_poke p LX_LINE line )
    ( __lex_one # i p LX_CUR )
}

// Shift cur ← peek ← peek2 ← peek3 ← peek4; reload tail. Drops the
// old cur (leaks its val string — same as the C version).
@ nurl_lex_advance i h → v {
    : s p # s h
    ? != 0 ( nurl_peek p + LX_PEEK TF_VALID ) {
        ( __tok_shift # i p LX_PEEK LX_CUR )
        ? != 0 ( nurl_peek p + LX_PEEK2 TF_VALID ) {
            ( __tok_shift # i p LX_PEEK2 LX_PEEK )
            ? != 0 ( nurl_peek p + LX_PEEK3 TF_VALID ) {
                ( __tok_shift # i p LX_PEEK3 LX_PEEK2 )
                ? != 0 ( nurl_peek p + LX_PEEK4 TF_VALID ) {
                    ( __tok_shift # i p LX_PEEK4 LX_PEEK3 )
                    ( nurl_poke p + LX_PEEK4 TF_VALID 0 )
                } {
                    ( nurl_poke p + LX_PEEK3 TF_VALID 0 )
                }
            } {
                ( nurl_poke p + LX_PEEK2 TF_VALID 0 )
            }
        } {
            ( nurl_poke p + LX_PEEK TF_VALID 0 )
        }
    } {
        ( __lex_one # i p LX_CUR )
    }
}

@ nurl_lex_peek_type i h → i {
    : s p # s h
    ? == 0 ( nurl_peek p + LX_PEEK TF_VALID ) {
        ( __lex_one # i p LX_PEEK )
    } {}
    ^ ( nurl_peek p + LX_PEEK TF_TYPE )
}

// Companion to nurl_lex_peek_type: return the lex VALUE of the
// LX_PEEK slot (the token AFTER the current one). Used by the
// borrow-checker's Phase 5+ field-access aliasing detection to
// recover the root identifier of a `. obj field` argument
// expression without rolling the current-token state forward.
// strdup'd, owned by the caller (mirrors nurl_lex_val).
@ nurl_lex_peek_val i h → s {
    : s p # s h
    ? == 0 ( nurl_peek p + LX_PEEK TF_VALID ) {
        ( __lex_one # i p LX_PEEK )
    } {}
    ^ # s ( strdup # s ( nurl_peek p + LX_PEEK TF_VAL ) )
}

@ nurl_lex_peek2_type i h → i {
    : s p # s h
    ? == 0 ( nurl_peek p + LX_PEEK TF_VALID ) { ( __lex_one # i p LX_PEEK ) } {}
    ? == 0 ( nurl_peek p + LX_PEEK2 TF_VALID ) { ( __lex_one # i p LX_PEEK2 ) } {}
    ^ ( nurl_peek p + LX_PEEK2 TF_TYPE )
}

@ nurl_lex_peek3_type i h → i {
    : s p # s h
    ? == 0 ( nurl_peek p + LX_PEEK TF_VALID ) { ( __lex_one # i p LX_PEEK ) } {}
    ? == 0 ( nurl_peek p + LX_PEEK2 TF_VALID ) { ( __lex_one # i p LX_PEEK2 ) } {}
    ? == 0 ( nurl_peek p + LX_PEEK3 TF_VALID ) { ( __lex_one # i p LX_PEEK3 ) } {}
    ^ ( nurl_peek p + LX_PEEK3 TF_TYPE )
}

@ nurl_lex_peek4_type i h → i {
    : s p # s h
    ? == 0 ( nurl_peek p + LX_PEEK TF_VALID ) { ( __lex_one # i p LX_PEEK ) } {}
    ? == 0 ( nurl_peek p + LX_PEEK2 TF_VALID ) { ( __lex_one # i p LX_PEEK2 ) } {}
    ? == 0 ( nurl_peek p + LX_PEEK3 TF_VALID ) { ( __lex_one # i p LX_PEEK3 ) } {}
    ? == 0 ( nurl_peek p + LX_PEEK4 TF_VALID ) { ( __lex_one # i p LX_PEEK4 ) } {}
    ^ ( nurl_peek p + LX_PEEK4 TF_TYPE )
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

// check_generic_bounds: at a generic call site `( f [Ta...] … )`, verify
// each bounded type parameter's concrete type implements the required
// trait(s). Dispatch already works through monomorphisation; this turns
// a missing impl from a cryptic unresolved-call link error into a clear
// compile-time diagnostic at the bound. No-op for unbounded generics.
@ check_generic_bounds i lex s fname s type_args → v {
    : ~ s tp_rest ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
    : ~ s ta_rest type_args
    ~ != 0 ( nurl_str_len tp_rest ) {
        : s tp ( str_first_word tp_rest )
        = tp_rest ( str_skip_word tp_rest )
        : s ta ( str_first_word ta_rest )
        = ta_rest ( str_skip_word ta_rest )
        : s bounds ( nurl_sym_get g_generic_syms ( nurl_str_cat3 fname `__bound__` tp ) )
        ? & != 0 ( nurl_str_len bounds ) != 0 ( nurl_str_len ta ) {
            : s ta_llvm ( nurl_src_to_llvm ta )
            : ~ s br bounds
            ~ != 0 ( nurl_str_len br ) {
                : s bt ( str_first_word br )
                = br ( str_skip_word br )
                ? == 0 ( nurl_str_len ( nurl_sym_get g_trait_syms ( nurl_str_cat3 bt `##` ta_llvm ) ) )
                { : s m1 ( nurl_str_cat4 `type '` ta `' does not implement trait '` bt )
                    : s m2 ( nurl_str_cat3 m1 `' required by bound ` ( nurl_str_cat3 tp `: ` bt ) )
                    ( die lex ( nurl_str_cat3 m2 ` on generic '` ( nurl_str_cat fname `'` ) ) ) }
                {}
            }
        } {}
    }
}

// ── Volatile MMIO intrinsics ───────────────────────────────────────
// `( volatile_load *T p )` → T  and  `( volatile_store *T p T val )` → v
// emit `load volatile` / `store volatile`, so the optimiser never hoists
// (LICM), reorders, or elides a memory-mapped I/O access. This is the
// missing piece for spinning on a device status register at -O2 — without
// it the read is lifted out of the polling loop and the spin never ends.
// Pure IR (no runtime call), so they work on a freestanding target. The
// access width comes from the pointer's pointee type, so this one pair
// covers i8 / i16 / i32 / i64 MMIO. The stored value must already match
// the pointee width (cast at the call site, e.g. `# i32`).

// Strip the trailing '*' from a pointer LLVM type ("i32*" → "i32").
@ __ptr_pointee s pt → s {
    : i n ( nurl_str_len pt )
    ? & > n 0 == ( nurl_str_get pt - n 1 ) 42
    { ^ ( nurl_str_slice pt 0 - n 1 ) }
    { ^ pt }
}

@ __is_ptr_ty s pt → b {
    : i n ( nurl_str_len pt )
    ^ & > n 0 == ( nurl_str_get pt - n 1 ) 42
}

@ gen_volatile_load i lex i syms i cg → s {
    : s pv ( gen_operand lex syms cg )
    : s pt ( nurl_get_last_type )
    ( expect lex TT_RPAREN )
    ? ! ( __is_ptr_ty pt )
    { ( die lex `volatile_load expects a typed pointer argument (*T)` ) }
    {}
    : s et ( __ptr_pointee pt )
    : s r ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print r )
    ( nurl_print ` = load volatile ` ) ( nurl_print et )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt ) ) ( nurl_print ` ` ) ( nurl_print pv )
    ( emit_dbg_eol )
    ( nurl_set_last_type et )
    ^ r
}

@ gen_volatile_store i lex i syms i cg → s {
    : s pv ( gen_operand lex syms cg )
    : s pt ( nurl_get_last_type )
    ? ! ( __is_ptr_ty pt )
    { ( die lex `volatile_store expects a typed pointer first argument (*T)` ) }
    {}
    : s et ( __ptr_pointee pt )
    : s vv ( gen_operand lex syms cg )
    ( expect lex TT_RPAREN )
    ( nurl_print `  store volatile ` ) ( nurl_print et )
    ( nurl_print ` ` ) ( nurl_print vv ) ( nurl_print `, ` )
    ( nurl_print ( nurl_llty pt ) ) ( nurl_print ` ` ) ( nurl_print pv )
    ( emit_dbg_eol )
    ( nurl_set_last_type `void` )
    ^ `void`
}

// Does the call's argument list (lexer at the first argument) use any
// `name:` label at the call's top level? A token scan with bracket-depth
// tracking; restores the lexer position. `IDENT :` at depth 0 is a named
// argument (a bare `:` never appears in a positional arg expression).
@ __kw_has_named i lex → b {
    : i save ( nurl_lex_cur_start lex )
    : ~ i depth 0
    : ~ b found F
    : ~ b done F
    ~ ! done {
        : i tt ( nurl_lex_type lex )
        ? == tt TT_EOF { = done T } {
            ? | | == tt TT_LPAREN == tt TT_LBRACK == tt TT_LBRACE
            { = depth + depth 1 ( nurl_lex_advance lex ) } {
                ? == tt TT_RPAREN
                { ? == depth 0 { = done T } { = depth - depth 1 ( nurl_lex_advance lex ) } } {
                    ? | == tt TT_RBRACK == tt TT_RBRACE
                    { = depth - depth 1 ( nurl_lex_advance lex ) } {
                        ? & & == depth 0 ( is_ident_tok tt ) == ( nurl_lex_peek_type lex ) TT_COLON
                        { = found T = done T }
                        { ( nurl_lex_advance lex ) } } } } }
    }
    ( nurl_lex_set_pos lex save )
    ^ found
}

// Per-call scratch key for the argstr piece chosen for parameter `i`.
// `seq` is a unique per-call id (g_func_count) so nested kwargs calls
// (an argument that is itself a kwargs call) never clobber each other.
@ __kw_slot_key i sq i i → s {
    ^ ( nurl_str_cat4 `__kwslot_` ( nurl_str_int sq ) `_` ( nurl_str_int i ) )
}

// argstr piece for parameter k that was not supplied: its default, or a
// missing-argument error.
@ __kw_default_or_die i lex i syms i cg s fname i k → s {
    : s dsrc ( nurl_sym_get syms ( __kw_key fname `pd` k ) )
    ? == 0 ( nurl_str_len dsrc )
    { ( die lex ( nurl_str_cat3
        `call to '` fname
        ( nurl_str_cat3 `' is missing required argument '`
        ( nurl_sym_get syms ( __kw_key fname `pn` k ) ) `'` ) ) ) }
    {}
    ^ ( __kw_emit_default syms cg dsrc )
}

// Named-argument call path. Evaluates each argument (positional or
// `name:`-labelled) in source order, then assembles the call with values
// in PARAMETER order, filling omitted parameters from their defaults.
// Restricted to ordinary @-functions with no inout/sink parameters
// (guarded by the caller); generics/FFI/variadic never reach here.
@ gen_call_kwargs i lex i syms i cg s fname → s {
    : i kw_n ( nurl_str_to_int ( nurl_sym_get syms ( nurl_str_cat fname `__kw_n` ) ) )
    = g_func_count + g_func_count 1
    : i kwseq g_func_count
    : ~ s owned_temps ``
    : ~ i posk 0
    : ~ b seen_named F
    ~ != ( nurl_lex_type lex ) TT_RPAREN {
        : i tt ( nurl_lex_type lex )
        : b named & ( is_ident_tok tt ) == ( nurl_lex_peek_type lex ) TT_COLON
        : ~ i slot -1
        ? named
        { = seen_named T
            : s aname ( nurl_lex_val lex )
            ( nurl_lex_advance lex )  // name
            ( nurl_lex_advance lex )  // ':'
            : ~ i j 0
            ~ < j kw_n {
                ? ( seq ( nurl_sym_get syms ( __kw_key fname `pn` j ) ) aname )
                { = slot j = j kw_n } { = j + j 1 }
            }
            ? == slot -1
            { ( die lex ( nurl_str_cat3 `call to '` fname
                ( nurl_str_cat3 `' has no parameter named '` aname `'` ) ) ) }
            {}
        }
        { ? seen_named
            { ( die lex `positional argument after a named argument is not allowed` ) } {}
            = slot posk
            = posk + posk 1
        }
        : s av ( gen_operand lex syms cg )
        : s at ( nurl_get_last_type )
        ( nurl_sym_def syms ( __kw_slot_key kwseq slot ) ( nurl_str_cat3 at ` ` av ) )
        ? & & != 0 g_auto_drop_strings ( seq ( nurl_llty at ) `i8*` )
        ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` )
        { = owned_temps ? == 0 ( nurl_str_len owned_temps ) av ( nurl_str_cat3 owned_temps ` ` av ) }
        {}
    }
    ( expect lex TT_RPAREN )
    : ~ s argstr ``
    : ~ i k 0
    ~ < k kw_n {
        : s piece ( nurl_sym_get syms ( __kw_slot_key kwseq k ) )
        : s use_piece ? != 0 ( nurl_str_len piece ) piece ( __kw_default_or_die lex syms cg fname k )
        = argstr ? == 0 ( nurl_str_len argstr ) use_piece ( nurl_str_cat3 argstr `, ` use_piece )
        = k + k 1
    }
    // Result metadata — mirror gen_call's ordinary-call setup so the
    // caller's `??` / try / let-binding sees the right payload + ownership.
    ( nurl_sym_def syms `__last_nurl_call__` ( nurl_sym_get syms ( nurl_str_cat fname `__nurl_ret` ) ) )
    ( nurl_sym_def syms `__last_call_res_t_llvm__` ( nurl_sym_get syms ( nurl_str_cat fname `__res_t_llvm` ) ) )
    ( nurl_sym_def syms `__last_call_res_e_llvm__` ( nurl_sym_get syms ( nurl_str_cat fname `__res_e_llvm` ) ) )
    ( nurl_sym_def syms `__last_call_opt_nurl_t__` ( nurl_sym_get syms ( nurl_str_cat fname `__opt_nurl_t` ) ) )
    ( nurl_sym_def syms `__last_call_ret_owned__` ( nurl_sym_get syms ( nurl_str_cat fname `__ret_owned` ) ) )
    // A4c: propagate the callee's returned struct owned-field list so the
    // caller's `: T x ( f )` re-registers them for drop.
    ( nurl_sym_def syms `__last_call_ret_struct_fields__` ( nurl_sym_get syms ( nurl_str_cat fname `__ret_owned_fields` ) ) )
    // Borrow provenance: the result is a borrow if the callee is marked
    // ret_borrow, or it is a vec_get* accessor (which returns a borrow of
    // an element the Vec still owns). The flag only changes behaviour for
    // an auto-Drop enum binding/match downstream — inert otherwise.
    ( nurl_sym_def syms `__last_value_borrow__`
    ? | != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__ret_borrow` ) ) )
    != 0 ( nurl_str_starts fname `vec_get` ) `1` `` )
    : s rl ( nurl_sym_get syms fname )
    : s rlt ? == 0 ( nurl_str_len rl ) `i64` rl
    ? ( seq rlt `void` )
    { ( nurl_print `  call void @` ) ( nurl_print fname )
        ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
        ( mem_drop_arg_temps owned_temps )
        ( nurl_set_last_type `void` )
        ^ `undef` }
    {}
    : s res ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print res ) ( nurl_print ` = call ` ) ( nurl_print ( nurl_llty rlt ) )
    ( nurl_print ` @` ) ( nurl_print fname )
    ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
    ( mem_drop_arg_temps owned_temps )
    ( nurl_set_last_type rlt )
    ^ res
}

// The arg_idx-th entry of a `;`-joined param-type-source list (empty when
// out of range).
@ __ptypes_nth s lst i idx → s {
    : ~ s cur lst
    : ~ i k 0
    ~ < k idx { = cur ( seplist_rest cur ) = k + k 1 }
    ^ ( seplist_first cur )
}

// A one-level pointer-depth mismatch on an identical base — `%X` vs `%X*`
// (or `i8` vs `i8*`). This is exactly the "passed `*T` where a `T` value is
// expected, or vice versa" miscompile class (the dchannel / SWIM family);
// it has zero false positives because the bases must be byte-identical
// apart from the single trailing `*`.
@ __arg_ptr_depth_mismatch s at s pt → b {
    ? | == 0 ( nurl_str_len at ) == 0 ( nurl_str_len pt ) { ^ F } {}
    // Compare LOWERED spellings so a `*u` (u8*) passed where a signed
    // `i8` value is expected still flags as a depth mismatch.
    : s at_ll ( nurl_llty at )
    : s pt_ll ( nurl_llty pt )
    ^ | ( seq at_ll ( nurl_str_cat pt_ll `*` ) ) ( seq pt_ll ( nurl_str_cat at_ll `*` ) )
}

// A `String` value (`%String`, a headered/managed string) and a raw
// C-string (`s`, i8* — the bare char data pointer, e.g. from string_data)
// are DISTINCT types. They are ABI-compatible enough that clang accepts a
// call passing one where the other is declared, but reinterpreting a
// String's payload pointer as a managed String (or vice versa) is silent
// UB — a wild-pointer crash the moment the callee reads the "other"
// representation. Flag the confusion in either direction at call time.
@ __arg_str_cstr_mismatch s at s pt → b {
    ^ | & ( seq ( nurl_llty at ) `i8*` ) ( seq pt `%String` )
    & ( seq at `%String` ) ( seq ( nurl_llty pt ) `i8*` )
}

// A NAMED aggregate LLVM type: `%Name` (a struct / enum handle), NOT a
// pointer (`…*`) and NOT a bare scalar (i64/double/i1/i8 carry no `%`).
@ __is_named_agg s t → b {
    ? == 0 ( nurl_str_len t ) { ^ F } {}
    ? != ( nurl_str_get t 0 ) 37 { ^ F } {}  // leading '%'
    ^ != ( nurl_str_get t - ( nurl_str_len t ) 1 ) 42  // not a pointer
}

// Two DIFFERENT named aggregates passed by value — e.g. a `B` value where
// an `A` is declared. clang silently coerces the call (reads the foreign
// struct's leading fields as the declared type), a silent miscompile.
// Both sides must be `%`-named aggregates so scalars/pointers and the
// enum↔i64 / numeric-width coercions are never touched.
@ __arg_named_struct_mismatch s at s pt → b {
    ^ & & ( __is_named_agg at ) ( __is_named_agg pt ) ! ( seq at pt )
}

// Exactly one operand lowers to a pointer, the other to a non-pointer
// scalar (i64/i32/double/i1/i8…). Catches the different-base pointer↔scalar
// class that __arg_ptr_depth_mismatch misses — e.g. an `i8*` string passed
// where an `i64` is declared (`( add 1 \`two\` )`), or an integer passed
// where a pointer is declared. Named aggregates and String have their own
// checks, so a side that is a `%Name` value is excluded here to avoid
// overlapping errors and the enum↔i64 lowering.
@ __arg_ptr_scalar_mismatch s at s pt → b {
    ? | == 0 ( nurl_str_len at ) == 0 ( nurl_str_len pt ) { ^ F } {}
    : s at_ll ( nurl_llty at )
    : s pt_ll ( nurl_llty pt )
    ? | ( __is_named_agg at_ll ) ( __is_named_agg pt_ll ) { ^ F } {}
    ^ != ( is_ptr_ty at_ll ) ( is_ptr_ty pt_ll )
}

@ gen_call i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s fname ( nurl_lex_val lex )
    // Lint: the callee is both a global reference (unused-function) and,
    // when it names a local closure binding, a read of it (unused-binding).
    // gen_call consumes the name directly, bypassing gen_ident, so record
    // both here.
    ( lint_note_used fname )
    ( lint_note_read fname )
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
    // Volatile MMIO intrinsics — intercepted before normal call dispatch.
    // lex is positioned at the first argument.
    ? ( seq fname `volatile_load` )
    { ^ ( gen_volatile_load lex syms cg ) }
    {}
    ? ( seq fname `volatile_store` )
    { ^ ( gen_volatile_store lex syms cg ) }
    {}
    // Dynamic trait object construction `( dyn Trait v )` (docs/spec.md §4.9).
    // Intercepted only when `dyn` is followed by a known trait name, so a
    // user function that happens to be named `dyn` still calls through.
    ? & ( seq fname `dyn` ) ( is_ident_tok ( nurl_lex_type lex ) )
    { : s __dtn ( nurl_lex_val lex )
        ? != 0 ( nurl_str_len ( nurl_sym_get g_trait_syms ( nurl_str_cat __dtn `__istrait` ) ) )
        { ^ ( gen_dyn_construct lex syms cg ) }
        {} }
    {}
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
    : ~ s call_name fname
    : ~ s call_targs ``
    ? == ( nurl_lex_type lex ) TT_LBRACK
    { ( nurl_lex_advance lex )  // consume '['
        : ~ s type_args ``
        : ~ s mangle_sfx ``
        ~ != ( nurl_lex_type lex ) TT_RBRACK {
            : i tt_arg ( nurl_lex_type lex )
            : ~ s ta ``
            // A bare anonymous slice (`[ T`) cannot be mangled as a call
            // type-argument (the base path below would capture the lone `[`).
            // Reject it with the documented cure rather than emitting IR that
            // only clang rejects. See spec.md §7.5 / grammar.ebnf generic_arg.
            ? == tt_arg TT_LBRACK
            { ( die lex `a slice type '[ T' cannot be a generic type argument — wrap it in a named struct (e.g. ': Buf [T] { [ T xs }') and instantiate that` ) }
            {}
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
            {  // Base or prefix-compound (`?T` / `??T` / `*T`) type arg.
                // capture_type_arg_src keeps a compound arg as one word so
                // it substitutes whole into the generic body; nurl_lex_val
                // alone would grab only the leading `?` / `*`.
                = ta ( capture_type_arg_src lex )
                // Lint: `vec_len [Header] …` references the Header
                // type — this path bypasses parse_type, so note it
                // here or a types-only import looks unused.
                ( lint_note_used_type_word ta )
            }
            = type_args ? == 0 ( nurl_str_len type_args ) ta
            ( nurl_str_cat type_args ( nurl_str_cat ` ` ta ) )
            = mangle_sfx ( nurl_str_cat mangle_sfx ( nurl_str_cat `__` ( mangle_src_word ta ) ) )
        }
        ( expect lex TT_RBRACK )
        : s mangled ( nurl_str_cat fname mangle_sfx )
        = call_targs type_args
        // Trait-bound check: each `A: Trait` tparam's concrete type must
        // have an impl of Trait (no-op for unbounded generics).
        ( check_generic_bounds lex fname type_args )
        // Dedup uses a global key (g_generic_syms is scope-free) because
        // local `syms` is push/popped per block — registering ret_ty in
        // syms inside a loop body would vanish when that block ends, and
        // the next call site outside the loop would defer again.
        : s gkey ( nurl_str_cat `__inst_` mangled )
        : s g_already ( nurl_sym_get g_generic_syms gkey )
        // Both branches below resolve the instance's return type via
        // compute_generic_ret_ty (directly, or inside defer_instantiation),
        // whose parse_type leaves the SUBSTITUTED option/result inner-type
        // tokens in g_res_type_syms. Reset first, then persist the option
        // inner token under the mangled name so a direct-call `?? ( call )`
        // match can recover signedness. The dedup-skip path runs neither
        // compute, leaving the marker empty — so guard the store and keep
        // the value recorded on this instance's first call in scope.
        ( nurl_sym_def g_res_type_syms `__last_opt_nurl_t__` `` )
        ? == 0 ( nurl_str_len g_already )
        { ( defer_instantiation lex fname mangled type_args syms )
            ( nurl_sym_def g_generic_syms gkey `1` ) }
        { : s already ( nurl_sym_get syms mangled )
            ? == 0 ( nurl_str_len already )
            { : s rt ( compute_generic_ret_ty fname type_args )
                ( nurl_sym_def syms mangled rt ) }
            {} }
        : s mont ( nurl_sym_get g_res_type_syms `__last_opt_nurl_t__` )
        ? != 0 ( nurl_str_len mont )
        { ( nurl_sym_def syms ( nurl_str_cat mangled `__opt_nurl_t` ) mont ) }
        {}
        // The monomorph's SUBSTITUTED return type (recorded above via
        // compute_generic_ret_ty) is the raw internal repr — `u32` for an
        // unsigned-returning generic — so an enclosing `# i ( gmax [u32]
        // … )` reads the signedness off the return type itself.
        = call_name mangled
    }
    {}
    : ~ s argstr ``
    : ~ i first 1
    : ~ s first_arg_type ``
    // Dynamic-dispatch receiver bookkeeping: the first argument's value and the
    // remaining args as their own list, so a `%dyn.Trait` receiver can be split
    // from the trailing args without re-parsing the comma-joined argstr.
    : ~ s first_arg_val ``
    : ~ s rest_argstr ``
    // Variadic FFI (grammar v1.9): if gen_ffi_decl tagged this function
    // with `<fname>__variadic`, apply C default argument promotions to
    // every arg whose 0-based index is >= the fixed-param count. FFI
    // decls are never generic, so the variadic flag is keyed on fname
    // rather than the mangled call_name.
    : b is_variadic ( seq ( nurl_sym_get syms ( nurl_str_cat fname `__variadic` ) ) `1` )
    : s vf_str ( nurl_sym_get syms ( nurl_str_cat fname `__variadic_fixed` ) )
    : i fixed_count ? == 0 ( nurl_str_len vf_str ) 0 ( nurl_str_to_int vf_str )
    // Closure-escape gate (docs/MEMORY.md §2.3).
    // These four callees take an argument that outlives the current
    // scope — pushing into a heap-backed container or detaching onto a
    // worker thread. A value that is a *stack reference* (a closure
    // capturing a binding by pointer, or an aggregate / binding
    // holding one — see the escape-analysis section near
    // borrowck_fn_end) MUST NOT escape through any of these without
    // first being moved to a heap-backed handle, or the captured
    // stack slot dangles the moment its owning function returns. The
    // check is --borrowck-gated.
    : b is_escape_call | | |
    ( seq fname `vec_push` )
    ( seq fname `vec_insert` )
    ( seq fname `vec_set` )
    ( seq fname `thread_spawn` )
    // A `*_free` destructor consumes (frees) its first argument.
    // `nurl_free` is excluded — it frees raw *T / i8* FFI memory,
    // which the borrow checker does not track.
    : b is_consume_call & ( bck_is_destructor_name fname )
    ! ( seq fname `nurl_free` )
    : ~ i arg_idx 0
    // Space-separated 0-based indices of the callee's `inout`
    // parameters (recorded into g_fn_inout by gen_fn_decl_concrete as
    // the callee is compiled). An argument at one of these positions
    // is passed by address — see the per-argument handling below.
    // Empty for an ordinary function.
    : ~ s callee_inout ( nurl_sym_get g_fn_inout call_name )
    // Indices of the callee's `sink` parameters — an argument there
    // is consumed (move-checked at the call site).
    : ~ s callee_sink ( nurl_sym_get g_fn_sink call_name )
    // Indices of the callee's *escaping* parameters — ones the callee's
    // body stores into a heap container or detaches onto a thread
    // (vec_push / vec_insert / vec_set / thread_spawn). Inferred per
    // function in codegen order (like the auto-sink summary) and
    // consulted below: a stack reference handed to such a parameter
    // escapes through the callee, the interprocedural form of §2.3.
    : ~ s callee_escapes ( nurl_sym_get g_fn_escapes call_name )
    // Indices of parameters the callee may RETURN — used after the
    // call to propagate a stack reference out through the result
    // (docs/MEMORY.md §2.8). Empty for a function that returns a fresh
    // value.
    : ~ s callee_ret_param ( nurl_sym_get g_fn_ret_param call_name )
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
    ? & == 0 ( nurl_str_len callee_escapes ) ! ( seq call_name fname )
    { = callee_escapes ( nurl_sym_get g_fn_escapes fname ) }
    {}
    ? & == 0 ( nurl_str_len callee_ret_param ) ! ( seq call_name fname )
    { = callee_ret_param ( nurl_sym_get g_fn_ret_param fname ) }
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
    // Keyword-args — named call arguments. When the callee is an ordinary
    // @-function (kw_n recorded) with no inout/sink parameters, not
    // shadowed by a local, and the call uses `name:` labels, route to the
    // reordering path. A `name:` label never appears at a positional call's
    // top level, so legacy calls never divert → byte-identical codegen.
    ? & & & & != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__kw_n` ) ) )
    == 0 ( nurl_str_len callee_inout )
    == 0 ( nurl_str_len callee_sink )
    == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__ptr` ) ) )
    ( __kw_has_named lex )
    { ^ ( gen_call_kwargs lex syms cg fname ) }
    {}
    : ~ s owned_arg_temps ``
    // Heap env pointers of inline closure-literal arguments passed to a
    // BORROWING (non-escaping) parameter — freed after the call returns
    // (docs/MEMORY.md §7.4). A literal handed to an escaping parameter
    // (thread_spawn detach, a helper that stores it) is left alone.
    : ~ s closure_envs_free ``
    // Space-separated referent depths of each positional argument, in
    // order (0 = not a stack reference). After the call, the result's
    // referent depth is the max over the callee's returned-parameter
    // indices — propagating a stack reference out (docs/MEMORY.md §2.8).
    : ~ s arg_refdepths ``
    // N-readers-XOR-1-writer: a binding passed to this call as
    // `inout` is mutably borrowed for the call's duration; it must
    // be the *exclusive* path to that value at the call. `p5_seen`
    // accumulates every bare-identifier argument and `p5_inout_seen`
    // the `inout` ones, so a binding that is both mutably borrowed
    // and aliased by another argument is flagged.
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
        // Reset __last_ident_name__ so the post-gen_expr check below
        // sees an ident only when this argument actually loaded one.
        ( nurl_sym_def syms `__last_ident_name__` `` )
        // Reset the escape side-channel so the escape check observes
        // only what THIS argument expression publishes.
        ( nurl_sym_def syms `__last_expr_refdepth__` `` )
        // Reset the closure-env side-channel so it reflects only an inline
        // closure literal generated for THIS argument.
        ( nurl_sym_def syms `__last_closure_env__` `` )
        // An argument at an `inout` parameter position is passed BY
        // ADDRESS, not by value. It must be a bare mutable (`: ~`)
        // binding — the callee mutates it in place. Pass the
        // binding's backing pointer (`__ptr`) typed `<T>*`; emit no
        // value load. Everything else is the ordinary by-value path.
        : b is_inout_arg ( str_contains_word callee_inout ( nurl_str_int arg_idx ) )
        // Exclusive-access check. A bare-identifier argument that is
        // mutably borrowed (`inout`) here must not be aliased by
        // another bare-identifier argument of the SAME call (whether
        // that other one is `inout` or a plain by-value read) — N
        // readers XOR 1 writer. Reading a binding through a nested
        // sub-expression argument is a known gap.
        // Strict mode: also consider the ROOT identifier of
        // `. obj field` argument expressions for the aliasing test
        // below. `obj` is the binding actually being touched; without
        // this the bare-identifier-only check misses
        // `( fn inout obj . obj field )`. Only consulted under
        // --strict-borrowck. The deep peek-val read is cheap because
        // the lexer's LX_PEEK slot is materialised on demand and we
        // don't advance.
        : ~ s bck_arg_root bck_arg_val
        ? & != g_strict_borrowck 0 == bck_arg_tt TT_DOT {
            : i pk_t ( nurl_lex_peek_type lex )
            ? ( is_ident_tok pk_t ) { = bck_arg_root ( nurl_lex_peek_val lex ) } {}
        } {}
        // Treat the field-access-rooted arg as a bare ident for
        // aliasing detection purposes when strict mode is on.
        : ~ b bck_treat_as_ident ( is_ident_tok bck_arg_tt )
        ? & != g_strict_borrowck 0 & == bck_arg_tt TT_DOT
        != 0 ( nurl_str_len bck_arg_root )
        { = bck_treat_as_ident T } {}
        ? & != g_borrowck 0 bck_treat_as_ident
        { ? | & is_inout_arg ( str_contains_word p5_seen bck_arg_root )
            & ! is_inout_arg ( str_contains_word p5_inout_seen bck_arg_root )
            { ( bck_esc_warn lex bck_arg_line ( nurl_str_cat3
                `'` bck_arg_root
                `' is both mutably borrowed (passed as 'inout') and aliased by another argument of the same call — exclusive access is violated` ) ) }
            {}
            = p5_seen ? == 0 ( nurl_str_len p5_seen )
            bck_arg_root ( nurl_str_cat3 p5_seen ` ` bck_arg_root )
            ? is_inout_arg
            { = p5_inout_seen ? == 0 ( nurl_str_len p5_inout_seen )
                bck_arg_root ( nurl_str_cat3 p5_inout_seen ` ` bck_arg_root ) }
            {}
            // Iterator invalidation: if this argument names a
            // container currently being iterated by an enclosing `~`
            // foreach, and the call mutates it — the receiver (arg 0)
            // of a stdlib container mutator, or any `inout` argument
            // — the loop's borrowed cursor would be invalidated. Uses
            // bck_arg_root so strict mode also catches
            // `( fn inout . obj field )` inside a `~ x : obj { ... }`
            // loop.
            : b fe_iterated ( str_contains_word
            ( nurl_sym_get g_bck `iter_containers` ) bck_arg_root )
            : b fe_mutates & == arg_idx 0 ( bck_is_container_mutator fname )
            ? & fe_iterated | is_inout_arg fe_mutates
            { ( bck_esc_warn lex bck_arg_line ( nurl_str_cat3
                `cannot mutate '` bck_arg_root
                `' while iterating over it — the '~' loop holds a borrow of the container; move the mutation out of the loop body` ) ) }
            {} }
        {}
        : ~ s av ``
        : ~ s at ``
        ? is_inout_arg
        { ? == bck_arg_tt TT_DOT
            {  // `inout` field target — `. obj field`.
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
                { ( die lex ( nurl_str_cat3 `inout argument '` bck_arg_val `' must be a mutable ': ~' binding — the callee mutates it in place` ) ) }
                {}
                ( nurl_lex_advance lex )
                // Lint: `inout name` passes the binding by address (no
                // gen_ident load) — mutating it in place is a use.
                ( lint_note_read bck_arg_val )
                = av iptr
                = at ( nurl_str_cat ity `*` )
            }
        }
        { ( nurl_sym_def syms `__in_call_arg__` `1` )
            = av ( gen_operand lex syms cg )
            ( nurl_sym_def syms `__in_call_arg__` `` )
            = at ( nurl_get_last_type )
        }
        // Closure-env reclamation: if this argument was an inline closure
        // literal that allocated a heap env, and the callee uses this
        // parameter as a pure borrow — it is in the callee's invoke-only
        // set (it only ever invokes it, never stores / returns / detaches
        // / decomposes it) — schedule the env to be freed after the call.
        // This is the POSITIVE signal: an unknown / forward callee has an
        // empty set, so the default is to NOT free (a leak, never a UAF).
        // thread_spawn and recover decompose the closure, so they are not
        // invoke-only and are correctly skipped.
        : s __cle ( nurl_sym_get syms `__last_closure_env__` )
        ? & != 0 ( nurl_str_len __cle )
        ( str_contains_word ( nurl_sym_get g_fn_invoke_only call_name ) ( nurl_str_int arg_idx ) )
        { = closure_envs_free ? == 0 ( nurl_str_len closure_envs_free )
            __cle ( nurl_str_cat3 closure_envs_free ` ` __cle ) }
        {}
        ( nurl_sym_def syms `__last_closure_env__` `` )
        // Closure-env reclamation: a tracked `:`-bound closure passed at a
        // NON-invoke-only position escapes (the callee may store / detach /
        // decompose it — thread_spawn, recover, a storing helper), so it is
        // no longer this frame's to free. Passing it to an invoke-only
        // (borrow) parameter leaves it tracked: it is freed at scope exit.
        ? & & ( is_ident_tok bck_arg_tt )
        ( str_contains_word ( nurl_sym_get syms `__owned_closure_envs__` ) bck_arg_val )
        ! ( str_contains_word ( nurl_sym_get g_fn_invoke_only call_name ) ( nurl_str_int arg_idx ) )
        { ( mem_own_closure_remove syms bck_arg_val ) }
        {}
        // Diagnose `nurl_str_len` vs `string_len` confusion.
        // `nurl_str_len` is the FFI to libc strlen and expects `s`
        // (i8*); passing a `%String` struct reads the struct bytes as
        // a pointer and returns garbage (bit us in manifest_parse).
        // `string_len` is the stdlib wrapper and expects a `%String`;
        // passing a raw i8* misreads the C-string pointer as a struct
        // handle. Both shapes are pure type mismatches detectable at
        // call time. Die — the result is silent UB otherwise.
        ? & == arg_idx 0 ( seq fname `nurl_str_len` )
        { ? ( seq at `%String` )
            { ( die lex `nurl_str_len expects 's' (i8* C-string), got %String. Use 'string_len' for String values.` ) }
            {} }
        {}
        ? & == arg_idx 0 ( seq fname `string_len` )
        { ? ( seq ( nurl_llty at ) `i8*` )
            { ( die lex `string_len expects %String, got 'i8*' (raw C-string). Use 'nurl_str_len' for raw C-string pointers.` ) }
            {} }
        {}
        // General pointer-vs-value argument check. For a non-generic @-fn
        // call (call_name == fname), compare this by-value argument's LLVM
        // type against the declared parameter type (recorded as source in
        // the pre-pass). Only a one-level pointer-depth mismatch on an
        // identical base is flagged — `*T` passed where a `T` value is
        // expected, or vice versa — the silent-miscompile class behind the
        // dchannel / SWIM bugs. `inout` args legitimately pass `<T>*` and
        // are skipped; generic callees (call_name ≠ fname) carry tparam
        // sources and are skipped too.
        // (generic fns now carry __ptypes_src too — for the width coercion
        // below — but their UNSUBSTITUTED tparam sources must not feed this
        // named-type comparison: `%Vec__u8` vs `( Vec A )` is not a clash.)
        ? & & & ( seq call_name fname ) ! is_inout_arg
        == 0 ( nurl_str_len ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) ) )
        != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__ptypes_src` ) ) )
        { : s __psrc ( __ptypes_nth ( nurl_sym_get syms ( nurl_str_cat fname `__ptypes_src` ) ) arg_idx )
            ? != 0 ( nurl_str_len __psrc )
            { : i __plx ( nurl_lex_new __psrc `<param>` )
                : s __pllvm ( parse_type __plx )
                // Detect pointer-ness from the LOWERED types so pointer
                // aliases with no literal `*` (e.g. `s` → i8*) are covered.
                // That is what lets the reverse case — a bare scalar passed
                // to an `s`/pointer parameter — reach the checks below, not
                // just an explicit `*T` argument.
                : b __at_ptr ( is_ptr_ty at )
                : b __ps_ptr ( is_ptr_ty __pllvm )
                ? | | | __at_ptr __ps_ptr ( seq at `%String` ) ( __is_named_agg at )
                { ? ( __arg_ptr_depth_mismatch at __pllvm )
                    { ( die lex ( nurl_str_cat3
                        ( nurl_str_cat4 `argument ` ( nurl_str_int + arg_idx 1 ) ` to '` fname )
                        ( nurl_str_cat4 `': value of type '` at `' passed where parameter expects '` __pllvm )
                        `' — pointer-vs-value mismatch (a '*T' was passed where a 'T' value is expected, or vice versa)` ) ) }
                    {}
                    ? ( __arg_str_cstr_mismatch at __pllvm )
                    { ( die lex ( nurl_str_cat3
                        ( nurl_str_cat4 `argument ` ( nurl_str_int + arg_idx 1 ) ` to '` fname )
                        ( nurl_str_cat4 `': value of type '` at `' passed where parameter expects '` __pllvm )
                        `' — String vs raw C-string mismatch: 'String' is a managed string, 's' (i8*) a bare char pointer; convert with 'string_data' (String→s) or 'string_from' (s→String)` ) ) }
                    {}
                    ? ( __arg_named_struct_mismatch at __pllvm )
                    { ( die lex ( nurl_str_cat3
                        ( nurl_str_cat4 `argument ` ( nurl_str_int + arg_idx 1 ) ` to '` fname )
                        ( nurl_str_cat4 `': value of type '` at `' passed where parameter expects '` __pllvm )
                        `' — wrong struct type passed by value (a value of one named type where a different one is declared); the call would silently reinterpret its fields` ) ) }
                    {}
                    ? ( __arg_ptr_scalar_mismatch at __pllvm )
                    { ( die lex ( nurl_str_cat3
                        ( nurl_str_cat4 `argument ` ( nurl_str_int + arg_idx 1 ) ` to '` fname )
                        ( nurl_str_cat4 `': value of type '` at `' passed where parameter expects '` __pllvm )
                        `' — pointer-vs-scalar type mismatch; NURL has no implicit conversion between a pointer and an integer/float (convert explicitly with '# T expr' if this is intended)` ) ) }
                    {} }
                {} }
            {} }
        {}
        // Escape analysis (docs/MEMORY.md §2.3 + §2.7). An argument
        // position *escapes* when the callee retains the value past the
        // call. Two sources:
        //   * a built-in heap/thread sink — the element of
        //     vec_push/vec_insert/vec_set (arg >= 1; arg 0 is the
        //     container, never a stack reference) or the thread_spawn
        //     closure (arg 0);
        //   * an inferred *escaping parameter* of a user function
        //     (callee_escapes) — the interprocedural case.
        // If the argument there is a stack reference (a closure
        // capturing a binding by pointer, or an aggregate / binding
        // holding one) it dangles the moment the surrounding function
        // returns — warn. And if the argument is itself a bare
        // parameter of the ENCLOSING function, this position makes that
        // parameter escape too: record it so the enclosing function's
        // own summary propagates the escape one level out (transitive,
        // in codegen order).
        : b vec_family_call | |
        ( seq fname `vec_push` ) ( seq fname `vec_insert` ) ( seq fname `vec_set` )
        : b builtin_escape_slot & is_escape_call ! & vec_family_call == arg_idx 0
        : b arg_pos_escapes | builtin_escape_slot
        ( str_contains_word callee_escapes ( nurl_str_int arg_idx ) )
        ? arg_pos_escapes
        { ( bck_esc_check_call_arg lex syms bck_arg_line
            ( nurl_sym_get syms `__last_ident_name__` ) fname )
            ? ( is_ident_tok bck_arg_tt )
            { ( bck_record_inferred_escape syms bck_arg_val ) } {} }
        {}
        // Thread-safety: the thread_spawn closure (arg 0) detaches onto a
        // worker thread. If it captures a non-Send value (an Rc — non-atomic
        // refcount), two threads racing on the control-block count is undefined
        // behaviour. Reject it and point at the thread-safe Arc. A named-binding
        // argument carries the flag via `<name>__closure_nonsend`; an inline
        // closure literal sets the `__last_closure_nonsend__` side-channel as it
        // is built just above.
        ? & ( seq fname `thread_spawn` ) builtin_escape_slot {
            : s __ts_ns ? ( is_ident_tok bck_arg_tt )
            ( nurl_sym_get syms ( nurl_str_cat bck_arg_val `__closure_nonsend` ) )
            g_last_closure_nonsend
            ? != 0 ( nurl_str_len __ts_ns )
            { ( die lex ( nurl_str_cat
                ( nurl_str_cat3 `thread_spawn closure captures '` __ts_ns `' which is an Rc — ` )
                `a non-atomic refcount is not safe to send across threads (two threads racing on the count is UB); use Arc (atomic) for a handle that crosses a thread boundary` ) ) }
            {}
        } {}
        // Record this argument's referent depth (for §2.8 return-escape
        // propagation below). Read the same side-channels the escape
        // check above consults — `__last_expr_refdepth__` (set by a
        // closure / aggregate literal) or the bound binding's own
        // refdepth — before the next argument resets them.
        : i bck_arg_rd ? != g_borrowck 0
        ( bck_expr_refdepth syms ( nurl_sym_get syms `__last_ident_name__` ) ) 0
        = arg_refdepths ? == 0 ( nurl_str_len arg_refdepths )
        ( nurl_str_int bck_arg_rd )
        ( nurl_str_cat3 arg_refdepths ` ` ( nurl_str_int bck_arg_rd ) )
        // Deferred interprocedural-escape (docs/MEMORY.md §3 forward /
        // generic). This argument is a stack reference (`bck_arg_rd > 0`)
        // that the inline check did NOT flag (`arg_pos_escapes` false —
        // the callee's escape summary is empty here, because the callee
        // is defined later, or is a generic not yet instantiated). The
        // callee must be a known user @-function (has `__arity`, not a
        // closure binding). Park the check; resolve_pending_escapes()
        // replays it against the final summary. If the callee turns out
        // non-escaping, the replay finds nothing — no false positive.
        ? & & & > bck_arg_rd 0 ! arg_pos_escapes
        != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__arity` ) ) )
        == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__ptr` ) ) )
        { : s __pe_rec ( nurl_str_cat3
            ( nurl_str_cat3 call_name ` ` fname )
            ( nurl_str_cat4 ` ` ( nurl_str_int arg_idx ) ` ` ( nurl_str_int bck_arg_line ) )
            ( nurl_str_cat ` ` ( nurl_lex_filename lex ) ) )
            : s __pe_cur ( nurl_sym_get g_pending_escape `l` )
            ( nurl_sym_def g_pending_escape `l`
            ? == 0 ( nurl_str_len __pe_cur ) __pe_rec
            ( nurl_str_cat3 __pe_cur ` ` __pe_rec ) ) }
        {}
        // A `*_free` destructor's first argument, when it is a bare
        // identifier, names a binding being consumed — stash it as a
        // move (flushed after the enclosing statement).
        ? & & is_consume_call == arg_idx 0 ( is_ident_tok bck_arg_tt )
        { ( bck_stash_move bck_arg_val ( nurl_lex_line lex ) )
            // Auto-sink inference: if the consumed bare-ident is the
            // enclosing fn's parameter, record its index so
            // gen_fn_decl_concrete can append it to g_fn_sink[fname].
            // Closes the indirect use-after-free case where
            // `( wrapper x )` frees `x` inside `wrapper`'s body and
            // the caller then reads `x`.
            ( bck_record_inferred_sink syms bck_arg_val ) }
        {}
        // A `sink` parameter consumes its argument. When the argument
        // is a bare-identifier binding, record it as moved so any
        // later use is a use-after-move. A binding that the compiler
        // auto-drops (owned slice / string / Drop value / struct with
        // owned fields) cannot yet be `sink`-passed — that needs
        // drop-ownership transfer to the callee (deferred); it is
        // rejected here rather than risking a double free.
        ? & ( str_contains_word callee_sink ( nurl_str_int arg_idx ) )
        ( is_ident_tok bck_arg_tt )
        { : s sink_ptr ( nurl_sym_get syms ( nurl_str_cat bck_arg_val `__ptr` ) )
            ? | | ( str_contains_word ( nurl_sym_get syms `__owned_slices__` ) bck_arg_val )
            ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) sink_ptr )
            | ( str_contains_word ( nurl_sym_get syms `__user_drops__` ) sink_ptr )
            ( str_contains_word ( nurl_sym_get syms `__owned_struct_fields__` ) sink_ptr )
            { ( die lex ( nurl_str_cat3
                `'` bck_arg_val
                `' is a compiler-auto-dropped value; passing it to a 'sink' parameter is not yet supported - pass a Vec or other manually-managed handle, or pass it as an ordinary parameter` ) ) }
            { ( bck_stash_move bck_arg_val ( nurl_lex_line lex ) )
                // Auto-sink cascade: if THIS fn passes its own
                // parameter as a sink arg to another fn, mark this
                // parameter as auto-sink too — the caller of this fn
                // likewise loses access to that arg afterwards.
                ( bck_record_inferred_sink syms bck_arg_val ) } }
        {}
        // Variadic position: promote BEFORE owned-temp tracking + argstr
        // append, since promotion replaces (at, av) with the widened pair.
        // i8*/i64/i32/double/pointers pass through variadic_promote_arg
        // unchanged.
        ? & is_variadic >= arg_idx fixed_count
        { = av ( variadic_promote_arg cg at av )
            = at ( variadic_promoted_type at )
        }
        {}
        // FFI arg width coercion (fixed positions only; vararg positions are
        // promoted above). If the callee is an FFI symbol and this argument's
        // integer width differs from the declared parameter type, emit the
        // trunc/sext so the emitted call type matches the `declare` — required
        // for a correct wasm import (see gen_ffi_decl's `ptypes` note).
        ? ! & is_variadic >= arg_idx fixed_count {
            : s __ffp ( nurl_sym_get syms ( nurl_str_cat fname `__ffi_params` ) )
            ? != 0 ( nurl_str_len __ffp ) {
                : s __want ( __nth_sep __ffp arg_idx )
                : i __ww ( int_width __want )
                : i __hw ( int_width at )
                : b __wp ( is_ptr_ty __want )
                : b __hp ( is_ptr_ty at )
                ? & != 0 ( nurl_str_len __want ) ! ( seq ( nurl_llty at ) ( nurl_llty __want ) ) {
                    ? & & > __ww 0 > __hw 0 != __ww __hw {
                        = av ( __emit_iwiden cg av at __want ) = at __want
                    } {
                        ? & __wp > __hw 0 {
                            // integer arg (e.g. a bare `0` / a handle held as i64)
                            // to a pointer parameter: inttoptr. A wasm call
                            // otherwise needs a function-signature bitcast, which
                            // is invalid → wasm-ld emits a trapping stub.
                            : s __nv ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print __nv )
                            ( nurl_print ` = inttoptr ` ) ( nurl_print ( nurl_llty at ) ) ( nurl_print ` ` ) ( nurl_print av )
                            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty __want ) ) ( nurl_print `\n` )
                            = av __nv = at __want
                        } {
                            ? & > __ww 0 __hp {
                                // pointer arg to an integer parameter: ptrtoint
                                : s __nv ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print __nv )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty at ) ) ( nurl_print ` ` ) ( nurl_print av )
                                ( nurl_print ` to ` ) ( nurl_print ( nurl_llty __want ) ) ( nurl_print `\n` )
                                = av __nv = at __want
                            } {}
                        }
                    }
                } {}
            } {}
            // NURL callee (no __ffi_params): the same width coercion
            // against the DECLARED parameter's source type. A sized-int
            // parameter (`u`, `u16`, `i32`, …) called with an i64 value —
            // any bare literal, or a plain `i` variable — used to emit
            // `call @f(i64 …)` against `define @f(i8 …)`. The native ABI
            // masks that (callee reads the low register bytes); on
            // wasm32 the signature mismatch makes wasm-ld emit a
            // trapping `_bitcast_invalid` stub. Generic calls substitute
            // this call's type args for bare tparam names first
            // (`vec_push [u] d 0` → param `A` → `u` → trunc to i8).
            ? == 0 ( nurl_str_len __ffp ) {
                : s __roster ( nurl_sym_get syms ( nurl_str_cat fname `__ptypes_src` ) )
                ? != 0 ( nurl_str_len __roster ) {
                    : ~ s __psrc ( __kw_trim ( __ptypes_nth __roster arg_idx ) )
                    ? ! ( seq call_name fname ) {
                        : ~ s __tpr ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
                        : ~ s __tar call_targs
                        ~ != 0 ( nurl_str_len __tpr ) {
                            : s __tp ( str_first_word __tpr )
                            = __tpr ( str_skip_word __tpr )
                            : s __ta ( str_first_word __tar )
                            = __tar ( str_skip_word __tar )
                            ? ( seq __psrc __tp ) { = __psrc __ta } {}
                        }
                    } {}
                    : s __wsrc ( src_int_ty __psrc )
                    ? != 0 ( nurl_str_len __wsrc ) {
                        : i __ww ( int_width __wsrc )
                        : ~ i __hw ( int_width at )
                        ? == __hw 0 { = __hw ( int_width ( src_int_ty at ) ) } {}
                        ? & & > __ww 0 > __hw 0 != __ww __hw {
                            = av ( __emit_iwiden cg av at __wsrc ) = at __wsrc
                        } {}
                    } {}
                } {}
            } {}
        } {}
        ? & & != 0 g_auto_drop_strings
        ( seq ( nurl_llty at ) `i8*` )
        ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` )
        { = owned_arg_temps ? == 0 ( nurl_str_len owned_arg_temps )
            av
            ( nurl_str_cat3 owned_arg_temps ` ` av ) }
        {}
        ? != first 0
        { = argstr ( nurl_str_cat3 ( nurl_llty at ) ` ` av )
            = first 0
            = first_arg_type at
            = first_arg_val av
        }
        { = argstr ( nurl_str_cat argstr ( nurl_str_cat4 `, ` ( nurl_llty at ) ` ` av ) )
            = rest_argstr ? == 0 ( nurl_str_len rest_argstr )
            ( nurl_str_cat3 at ` ` av )
            ( nurl_str_cat rest_argstr ( nurl_str_cat4 `, ` at ` ` av ) )
        }
        = arg_idx + arg_idx 1
    }
    // Keyword-args — default values. Fill omitted TRAILING parameters
    // with their declared defaults: when the callee recorded defaults
    // (`__kw_hasdef`) and the call supplied fewer positional args than
    // parameters, each default's single-token source is parsed here and
    // appended as an ordinary positional argument, so the arity check
    // below then passes. Stops at the first omitted parameter that has no
    // default, so a genuine missing argument still errors there. Existing
    // fully-supplied calls never enter the loop → byte-identical codegen.
    ? & ( seq ( nurl_sym_get syms ( nurl_str_cat fname `__kw_hasdef` ) ) `1` )
    ( seq call_name fname )
    { : s kw_n_s ( nurl_sym_get syms ( nurl_str_cat fname `__kw_n` ) )
        : i kw_n ? == 0 ( nurl_str_len kw_n_s ) 0 ( nurl_str_to_int kw_n_s )
        : ~ b kw_stop F
        ~ & & < arg_idx kw_n ! kw_stop
        != 0 ( nurl_str_len ( nurl_sym_get syms ( __kw_key fname `pd` arg_idx ) ) )
        { : s dsrc ( nurl_sym_get syms ( __kw_key fname `pd` arg_idx ) )
            : s argpiece ( __kw_emit_default syms cg dsrc )
            ? == 0 ( nurl_str_len argstr )
            { = argstr argpiece = first 0 }
            { = argstr ( nurl_str_cat3 argstr `, ` argpiece ) }
            = arg_idx + arg_idx 1
        }
    }
    {}
    // Unknown callee: nothing registered a return type for this name —
    // not an @-fn seen by scan_fn_sigs (this file or any '$'-import
    // processed so far), not an FFI extern, not a runtime builtin from
    // the register_builtins table, not an impl method (dispatched
    // below via g_impl_name_syms — exempted through `__impl_seen`),
    // and not a local closure / fn-pointer binding (no `__ptr`).
    // The legacy fallthrough assumed `i64` and emitted a call to an
    // undeclared symbol — invalid IR that surfaced as a clang error far
    // from the source, or (worse) linked-by-accident when the defining
    // file happened to be imported later in the unit AND the return
    // type happened to be i64. Mirror gen_ident's undefined-identifier
    // diagnostic so the error lands on the call site instead. Runs
    // while the lexer still sits on the closing ')' so the caret
    // points at this call.
    //
    // A pure-NURL stdlib helper (`nurl_str_cat` / `_cat3` / `_cat4` /
    // `_slice`) is pre-registered in init_syms for cross-module typing but
    // has no C body — so if the program never imported its module it is
    // undefined at link (clang: "use of undefined value '@nurl_str_cat'").
    // It carries a `__needs_stdlib` marker but no `__arity` (scan_fn_sigs, a
    // complete whole-program pre-pass, sets `__arity` for any real
    // definition before any call is generated). Name the missing import at
    // the call site instead of leaking the clang error.
    ? & != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__needs_stdlib` ) ) )
    == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__arity` ) ) )
    { ( die lex ( nurl_str_cat3
        ( nurl_str_cat3 `'` fname `' is defined in ` )
        ( nurl_sym_get syms ( nurl_str_cat fname `__needs_stdlib` ) )
        ` (a pure-NURL stdlib helper, not a runtime builtin) — add a '$' import of that file to use it.` ) ) }
    {}
    ? & & & == 0 ( nurl_str_len ( nurl_sym_get syms call_name ) )
    == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__ptr` ) ) )
    == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat fname `__arity` ) ) )
    == 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms ( nurl_str_cat fname `__impl_seen` ) ) )
    {  // A GENERIC function called with no `[T …]` type arguments lands
        // here — it carries `__tparams` but no `__arity` / mangled
        // call_name (NURL does not infer type args from value args). Name
        // the real cause instead of the misleading "unknown function".
        : s __gtp ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
        ? != 0 ( nurl_str_len __gtp )
        { ( die lex ( nurl_str_cat3
            ( nurl_str_cat3 `generic function '` fname `' needs explicit type argument(s): write ( ` )
            ( nurl_str_cat3 fname ` [` ( nurl_str_cat __gtp `] … ) ` ) )
            `— NURL does not infer generic type arguments from value arguments.` ) ) }
        { : s __sugg ( __suggest_ident syms fname )
            ? != 0 ( nurl_str_len __sugg )
            { ( die lex ( nurl_str_cat ( nurl_str_cat3
                `call to unknown function '` fname
                `' — did you mean '` )
                ( nurl_str_cat3 __sugg `'? If not: it is not defined in this file, not in any ` `'$'-imported file processed so far, and not a known FFI/builtin — add the missing '$' import, or check the spelling.` ) ) ) }
            { ( die lex ( nurl_str_cat3
                `call to unknown function '` fname
                `' — it is not defined in this file, not in any '$'-imported file processed so far, and not a known FFI/builtin. Add the missing '$' import (or move it above this file's import in the program), or check the spelling.` ) ) } } }
    {}
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
    // Escape analysis (docs/MEMORY.md §2.8): the call result is a stack
    // reference exactly when the callee RETURNS one of its parameters
    // (callee_ret_param) and the argument at that position was itself a
    // stack reference — the result then carries that argument's referent
    // depth, so `^ ( id ref )` / `( vec_push xs ( id ref ) )` dangle just
    // like the direct forms. Otherwise the result is not a stack
    // reference: clear the side-channel an argument closure / aggregate
    // literal may have left set, so the enclosing gen_let / gen_ret does
    // not mis-read `( f \ → v {…} )` as one.
    // Set the result's referent depth *authoritatively* — always a
    // number, never empty. An empty side-channel would let
    // bck_expr_refdepth fall back to the now-stale `__last_ident_name__`
    // (the last argument), so `^ ( f stackref )` mis-flagged the call
    // result as the argument's reference even when `f` returns a fresh
    // value. The explicit `0` says "this call result is not a stack
    // reference"; a positive depth says "it is, with this referent".
    : i __ret_rd ? & != g_borrowck 0 != 0 ( nurl_str_len callee_ret_param )
    ( bck_max_ret_refdepth callee_ret_param arg_refdepths ) 0
    ( nurl_sym_def syms `__last_expr_refdepth__` ( nurl_str_int __ret_rd ) )
    // Dynamic dispatch: a `%dyn.Trait` (or `%dyn.Trait*` inout) receiver whose
    // method `fname` is in the trait's flattened method set. Load the vtable
    // slot and call it indirectly through the uniform ABI `<ret>(i8* self, …)`.
    // Falls through when `fname` is not a trait method (e.g. an ordinary
    // function that merely takes a `%dyn.Trait` parameter).
    ? != 0 ( nurl_str_starts first_arg_type `%dyn.` )
    { : s __dbody ( nurl_str_slice first_arg_type 5 - ( nurl_str_len first_arg_type ) 5 )
        : b __dptr == ( nurl_str_get first_arg_type - ( nurl_str_len first_arg_type ) 1 ) 42
        : s __dtrait ? __dptr ( nurl_str_slice __dbody 0 - ( nurl_str_len __dbody ) 1 ) __dbody
        : i __slot ( dyn_method_slot __dtrait fname )
        ? >= __slot 0
        { : s __dynty ( nurl_str_cat `%dyn.` __dtrait )
            : ~ s __fat first_arg_val
            ? __dptr
            { : s __lf ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print __lf ) ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty __dynty ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty __dynty ) ) ( nurl_print `* ` ) ( nurl_print first_arg_val ) ( nurl_print `\n` )
                = __fat __lf }
            {}
            : s __data ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print __data ) ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty __dynty ) ) ( nurl_print ` ` ) ( nurl_print __fat ) ( nurl_print `, 0\n` )
            : s __vtp ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print __vtp ) ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty __dynty ) ) ( nurl_print ` ` ) ( nurl_print __fat ) ( nurl_print `, 1\n` )
            : i __vsz + ( dyn_flat_count __dtrait ) 1
            : s __vszs ( nurl_str_int __vsz )
            : s __arr ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print __arr ) ( nurl_print ` = bitcast i8* ` ) ( nurl_print __vtp ) ( nurl_print ` to [` ) ( nurl_print __vszs ) ( nurl_print ` x i8*]*\n` )
            : s __sp ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print __sp ) ( nurl_print ` = getelementptr [` ) ( nurl_print __vszs ) ( nurl_print ` x i8*], [` ) ( nurl_print __vszs ) ( nurl_print ` x i8*]* ` ) ( nurl_print __arr ) ( nurl_print `, i64 0, i64 ` ) ( nurl_print ( nurl_str_int __slot ) ) ( nurl_print `\n` )
            : s __fp ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print __fp ) ( nurl_print ` = load i8*, i8** ` ) ( nurl_print __sp ) ( nurl_print `\n` )
            : s __dt ( dyn_method_decltrait __dtrait fname )
            : s __parts ( dyn_subst_parts __dt fname `i64` )
            : s __ret ( pipe_first __parts )
            : s __fnty ( dyn_call_fnty __parts )
            : s __fnr ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print __fnr ) ( nurl_print ` = bitcast i8* ` ) ( nurl_print __fp ) ( nurl_print ` to ` ) ( nurl_print __fnty ) ( nurl_print `\n` )
            : s __cargs ? == 0 ( nurl_str_len rest_argstr ) ( nurl_str_cat `i8* ` __data ) ( nurl_str_cat4 `i8* ` __data `, ` rest_argstr )
            ? ( seq __ret `void` )
            { ( nurl_print `  call void ` ) ( nurl_print __fnr ) ( nurl_print `(` ) ( nurl_print __cargs ) ( nurl_print `)` ) ( emit_dbg_eol )
                ( mem_drop_arg_temps owned_arg_temps ) ( mem_drop_arg_temps closure_envs_free )
                ( nurl_set_last_type `void` )
                ^ `undef` }
            { : s __res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print __res ) ( nurl_print ` = call ` ) ( nurl_print ( nurl_llty __ret ) ) ( nurl_print ` ` ) ( nurl_print __fnr ) ( nurl_print `(` ) ( nurl_print __cargs ) ( nurl_print `)` ) ( emit_dbg_eol )
                ( mem_drop_arg_temps owned_arg_temps ) ( mem_drop_arg_temps closure_envs_free )
                ( nurl_set_last_type __ret )
                ^ __res }
        }
        {} }
    {}
    // Group F: impl method dispatch based on first arg's LLVM type
    : ~ s impl_key ( nurl_str_cat fname ( nurl_str_cat `##` first_arg_type ) )
    : ~ s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
    // `inout` receiver: the first argument is passed as `%T*`, but impls
    // are registered by the value type `%T` (g_impl_name_syms key
    // `method##%T`). On a miss with a pointer-typed first arg, retry with
    // the trailing `*` stripped so an `inout`/`sink` impl method still
    // dispatches. (Without this, applying `inout` pointerised the arg and
    // the dispatch fell through to an undefined bare `@method`.)
    ? & == 0 ( nurl_str_len impl_mangle_key )
    & > ( nurl_str_len first_arg_type ) 1
    == ( nurl_str_get first_arg_type - ( nurl_str_len first_arg_type ) 1 ) 42
    { : s __fa_base ( nurl_str_slice first_arg_type 0 - ( nurl_str_len first_arg_type ) 1 )
        = impl_key ( nurl_str_cat fname ( nurl_str_cat `##` __fa_base ) )
        = impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
    }
    {}
    ? != 0 ( nurl_str_len impl_mangle_key )
    { : s impl_ret ( nurl_sym_get g_impl_ret_syms impl_key )
        : s impl_name ( nurl_str_cat fname ( nurl_str_cat `__` impl_mangle_key ) )
        // Publish the callee's return side-channels (ownership, borrow, signedness,
        // try-propagation types) exactly like the Regular-call path below — the
        // impl-method dispatch used to skip them, leaking owned-string results
        // passed straight to another call and mishandling borrow/`u`/`!T E` returns.
        ( mem_propagate_call_ret_markers syms impl_name )
        ? ( seq impl_ret `void` )
        { ( nurl_print `  call void @` ) ( nurl_print impl_name )
            ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
            ( mem_drop_arg_temps owned_arg_temps ) ( mem_drop_arg_temps closure_envs_free )
            ( nurl_set_last_type `void` )
            ^ `undef`
        }
        { : s res ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = call ` ) ( nurl_print ( nurl_llty impl_ret ) )
            ( nurl_print ` @` ) ( nurl_print impl_name )
            ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
            ( mem_drop_arg_temps owned_arg_temps ) ( mem_drop_arg_temps closure_envs_free )
            ( nurl_set_last_type impl_ret )
            ^ res
        }
    }
    {}
    // Regular call
    : s rl ( nurl_sym_get syms call_name )
    : s rlt ? == 0 ( nurl_str_len rl ) `i64` rl
    // Publish the callee's return side-channels (NURL ret type + Result/opt
    // payload LLVM types for `??`/try, owned-string/-slice + struct-field
    // ownership for auto-drop, borrow provenance, return signedness). Shared
    // with the impl-method dispatch path above via one helper so no path can
    // silently omit a marker.
    ( mem_propagate_call_ret_markers syms call_name )

    // Check if this is a stored closure variable first
    : s var_ptr ( nurl_sym_get syms ( nurl_str_cat call_name `__ptr` ) )
    : s call_type ( nurl_sym_get syms call_name )
    : b has_var_ptr != 0 ( nurl_str_len var_ptr )
    : s call_type_ll ( nurl_llty call_type )
    : b is_fn_type | | | | != 0 ( nurl_str_starts call_type_ll `i64 (` ) != 0 ( nurl_str_starts call_type_ll `void (` ) != 0 ( nurl_str_starts call_type_ll `i8* (` ) != 0 ( nurl_str_starts call_type_ll `i8*(` ) != 0 ( nurl_str_starts call_type_ll `{` )
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
        ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty call_type ) )
        ( nurl_print `, ` ) ( nurl_print ( nurl_llty call_type ) ) ( nurl_print `* ` )
        ( nurl_print var_ptr ) ( nurl_print `\n` )

        : ~ s final_result ``
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
            ( nurl_print ` = call ` ) ( nurl_print ( nurl_llty fn_ret_type ) )
            ( nurl_print ` ` ) ( nurl_print loaded_closure )
            ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
            ( nurl_set_last_type fn_ret_type )
            = final_result res
        }
        ( mem_drop_arg_temps owned_arg_temps ) ( mem_drop_arg_temps closure_envs_free )
        final_result
    }
    { ? is_function_pointer
        {
            // This is a function pointer parameter
            : ~ s final_result ``
            ? ( str_contains call_type `{` )
            {  // Closure struct parameter
                = final_result ( call_closure_function var_llvm_val call_type argstr cg )
            }
            {  // Simple function pointer parameter - call directly
                : s fn_return_type ( extract_fn_ptr_return_type rlt )
                : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = call ` ) ( nurl_print ( nurl_llty fn_return_type ) )
                ( nurl_print ` ` ) ( nurl_print var_llvm_val )
                ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
                ( nurl_set_last_type fn_return_type )
                = final_result res
            }
            ( mem_drop_arg_temps owned_arg_temps ) ( mem_drop_arg_temps closure_envs_free )
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
            // Variadic FFI: the call must carry the callee's explicit
            // function type — `call i32 (i8*, ...) @printf(...)`. Without
            // it LLVM infers a NON-variadic callee type from the arg
            // list; the x86_64 SysV ABI happens to pass varargs the same
            // way so Linux works by luck, but Win64 requires variadic FP
            // args to be mirrored into the integer registers — printf %g
            // reads garbage from a float promoted at such a call site.
            : s va_sig ? is_variadic ( nurl_sym_get syms ( nurl_str_cat fname `__variadic_sig` ) ) ``
            : b has_va_sig != 0 ( nurl_str_len va_sig )
            ? ( seq rlt `void` )
            { ( nurl_print `  call void ` )
                ? has_va_sig { ( nurl_print `(` ) ( nurl_print va_sig ) ( nurl_print `) ` ) } {}
                ( nurl_print `@` ) ( nurl_print call_name )
                ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
                ( mem_drop_arg_temps owned_arg_temps ) ( mem_drop_arg_temps closure_envs_free )
                ( nurl_set_last_type `void` )
                `undef`
            }
            { : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = ` ) ( nurl_print tail_kw )
                ( nurl_print `call ` ) ( nurl_print ( nurl_llty rlt ) )
                ? has_va_sig { ( nurl_print ` (` ) ( nurl_print va_sig ) ( nurl_print `)` ) } {}
                ( nurl_print ` @` ) ( nurl_print call_name )
                ( nurl_print `(` ) ( nurl_print argstr ) ( nurl_print `)` ) ( emit_dbg_eol )
                ( mem_drop_arg_temps owned_arg_temps ) ( mem_drop_arg_temps closure_envs_free )
                // rlt is the raw internal return type (`u8` for a
                // u-returning callee), so an enclosing `# i ( f )` reads
                // the signedness straight off the type — argument
                // evaluation can no longer clobber it.
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
    // The condition is a value operand — a `^` here is a cascade.
    : ~ s cv ( gen_operand lex syms cg )
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
    : ~ s old_strs_t ``
    : ~ s old_structs_t ``
    : ~ s old_user_t ``
    : ~ s old_closure_t ( nurl_sym_get syms `__owned_closure_envs__` )
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
    // The arm body is a fresh tail position — `^` is legal here even if
    // this `?` was itself parsed as an operand.
    = g_ret_forbidden 0
    // Reset the ident side-channel so we can tell whether this arm's
    // value is a bare load of a named binding — if that binding is a
    // tracked owned string, its buffer ESCAPES the arm through the phi
    // below and its scheduled drop must be cancelled (see the phi
    // block). Copy the snapshot via nurl_str_cat: sym_get returns a
    // pointer into the arm scope's entry, which nurl_sym_pop frees.
    ( nurl_sym_def syms `__last_ident_name__` `` )
    : s tv ( gen_expr lex syms cg )
    : s tt2 ( nurl_get_last_type )
    : s t_retid ( nurl_str_cat ( nurl_sym_get syms `__last_ident_name__` ) `` )
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
        ( mem_drop_new_closure_envs syms cg old_closure_t )
        ( nurl_print `  br label %` ) ( nurl_print lend ) ( emit_dbg_eol )
    } {}
    ? != 0 g_auto_drop_strings { ( nurl_sym_pop syms ) } {}
    ( emit ( nurl_str_cat le `:` ) )
    : ~ s old_strs_e ``
    : ~ s old_structs_e ``
    : ~ s old_user_e ``
    : ~ s old_closure_e ( nurl_sym_get syms `__owned_closure_envs__` )
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
    = g_ret_forbidden 0
    // Mirror of the then-arm's escaping-ident snapshot above.
    ( nurl_sym_def syms `__last_ident_name__` `` )
    : s ev ( gen_expr lex syms cg )
    : s et2 ( nurl_get_last_type )
    : s e_retid ( nurl_str_cat ( nurl_sym_get syms `__last_ident_name__` ) `` )
    : s elbl ( nurl_sym_get syms `__cur_lbl__` )
    : i edr g_did_ret
    ? == edr 0
    { ? & != 0 g_auto_drop_strings ( seq et2 `void` )
        { ( mem_drop_new_strings syms cg old_strs_e )
            ( mem_drop_new_struct_fields syms cg old_structs_e )
            ( mem_drop_new_user_drops syms cg old_user_e ) } {}
        ( mem_drop_new_closure_envs syms cg old_closure_e )
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
    // Prefix-arity grammar: `?` consumed bare expressions for
    // then/else, but the very next token is `{`. Almost always the
    // n-ary `&`/`|` foot-gun: user wrote `? & a b c d { then } { else }`
    // intending an n-ary AND, but `& a b` only takes 2 operands so
    // `c` and `d` got consumed as the bare then/else, and the
    // `{ ... }` blocks then run as side-effect statements. Warn —
    // the program compiles but the conditional logic is wrong.
    ? == ( nurl_lex_type lex ) TT_LBRACE
    { ( warn lex `'?' consumed bare then/else values, but a '{ ... }' block follows. Likely too few '&'/'|' operators in the condition (each is BINARY — write '& & a b c d' for n-ary).` ) }
    {}
    // pick a consistent phi type: prefer the non-void live branch type;
    // if both live and types differ, fall back to void (no phi needed).
    // The `?`-result keeps the unsigned spelling when EITHER arm carries
    // it (NURL types match across arms, so signedness is the only way
    // they can differ; the OR is defensive — e.g. an i64 literal arm
    // beside a u64 arm), so an enclosing `# i ? c (# u …) (# u …)`
    // widens the selected value with zext. Arm-type agreement is
    // therefore judged on the LOWERED types.
    : b arms_u | ( ty_is_unsigned tt2 ) ( ty_is_unsigned et2 )
    : ~ s phi_ty ? != 0 tdr et2 tt2
    ? arms_u { = phi_ty ( ty_to_unsigned phi_ty ) } {}
    : b types_ok | != 0 tdr | != 0 edr ( seq ( nurl_llty tt2 ) ( nurl_llty et2 ) )
    : ~ s result `undef`
    ? == 0 g_did_ret
    { ? & ! ( seq phi_ty `void` ) types_ok
        { : s res ( nurl_cg_reg cg )
            // Ownership transfer out of the arms: an arm whose value is
            // a bare load of a tracked owned i8* binding hands that
            // buffer to the phi consumer — cancel the binding's
            // scheduled drop or the scope-exit free dangles every later
            // use of the phi value (bit the compiler itself: gen_cast's
            // `: s norm ? … xv ( nurl_cg_reg cg )` returned norm while
            // the epilogue freed xv). Worst case (ident was merely the
            // last load inside a trailing call) the buffer leaks —
            // never a use-after-free. Only arms live into the phi
            // transfer; a `^`-returning arm keeps its own path's drops.
            ? ( seq ( nurl_llty phi_ty ) `i8*` )
            { ? == 0 tdr
                { ( mem_remove_owned_str syms
                    ( nurl_sym_get syms ( nurl_str_cat t_retid `__ptr` ) ) ) }
                {}
                ? == 0 edr
                { ( mem_remove_owned_str syms
                    ( nurl_sym_get syms ( nurl_str_cat e_retid `__ptr` ) ) ) }
                {}
            }
            {}
            ? & != 0 tdr == 0 edr
            { ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = phi ` ) ( nurl_print ( nurl_llty phi_ty ) )
                ( nurl_print ` [ ` ) ( nurl_print ev )
                ( nurl_print `, %` ) ( nurl_print elbl ) ( nurl_print ` ]\n` )
            }
            { ? & == 0 tdr != 0 edr
                { ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = phi ` ) ( nurl_print ( nurl_llty phi_ty ) )
                    ( nurl_print ` [ ` ) ( nurl_print tv )
                    ( nurl_print `, %` ) ( nurl_print tlbl ) ( nurl_print ` ]\n` )
                }
                { ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = phi ` ) ( nurl_print ( nurl_llty phi_ty ) )
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
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty match_type ) )
        ( nurl_print ` ` ) ( nurl_print match_val )
        ( nurl_print `, ` ) ( nurl_print ( nurl_str_int + idx 1 ) ) ( nurl_print `\n` )
        // The i64 payload slot compares against the literal directly.
        : s cmp_reg ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print cmp_reg )
        ( nurl_print ` = icmp eq i64 ` ) ( nurl_print raw_reg )
        ( nurl_print `, ` ) ( nurl_print lit ) ( nurl_print `\n` )
        : s ok_label ( nurl_cg_lbl cg `litok` )
        ( nurl_print `  br i1 ` ) ( nurl_print cmp_reg )
        ( nurl_print `, label %` ) ( nurl_print ok_label )
        ( nurl_print `, label %` ) ( nurl_print fail_label ) ( emit_dbg_eol )
        ( nurl_print ok_label ) ( nurl_print `:\n` )
    }
}

// gen_select — Go-style `select` over channels, spelled `?? { … }`
// (a `??` whose scrutinee is immediately `{` has no value to match, so
// it is unambiguously a select; a normal match always has a scrutinee
// expression first). Each case is
//
//     [T] chexpr → bind { body }       // bind is a ?T (None ⇒ closed)
//     _          → { body }            // optional non-blocking default
//
// We desugar the whole construct into synthesised NURL source built from
// the verbatim user channel-exprs + bodies (extracted with
// nurl_lex_src_slice) and compile it through a sub-lexer that shares the
// same codegen + symbol table. So the normal pipeline handles the
// generic `chan_try_recv [T]`, the field/cast ops and every branch — no
// raw IR, no mangled names. The blocking rendezvous (arm / wait / fire /
// disarm) lives in stdlib/std/channel.nu.
//
// Lowering (no default):
//   { : i W ( select_waiter_new )
//     : i CTLk  # i . ( chexpr_k ) ctl          // once per case
//     : ~ b DONE F
//     ~ ! DONE {
//       ( select_waiter_prepare W )
//       ( chan_raw_arm CTLk W )                  // every case
//       ? ! DONE { : ?Tk bind ( chan_try_recv [Tk] ( chexpr_k ) )
//                  ? | ( opt_is_some [Tk] bind ) ( chan_raw_closed CTLk )
//                    { = DONE T <body_k> } {} } {}
//       ? ! DONE { ( select_waiter_wait W ) } {}
//       ( chan_raw_disarm CTLk W ) }            // every case
//     ( select_waiter_free W ) }
//
// With a `_` default arm there is no waiter and no loop: poll each case
// once, then run the default body.
@ gen_select i lex i syms i cg → s {
    ( expect lex TT_LBRACE )  // consume the '{'

    : s uid ( nurl_cg_lbl cg `sel` )
    : s w_name ( nurl_str_cat `__` ( nurl_str_cat uid `w` ) )
    : s done_name ( nurl_str_cat `__` ( nurl_str_cat uid `done` ) )

    : ~ s ctl_decls ``
    : ~ s arm_block ``
    : ~ s disarm_block ``
    : ~ s poll_block ``
    : ~ s default_body ``
    : ~ i has_default 0
    : ~ i bidx 0

    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        ? == ( nurl_lex_type lex ) TT_LBRACK {
            // ── [T] chexpr → bind { body } ──
            ( nurl_lex_advance lex )  // consume '['
            : i tstart ( nurl_lex_cur_start lex )
            : ~ i bdepth 1
            ~ > bdepth 0 {
                : i tt ( nurl_lex_type lex )
                ? == tt TT_EOF { ( die lex `unterminated [type] in select case` ) } {}
                ? == tt TT_LBRACK { = bdepth + bdepth 1 } {}
                ? == tt TT_RBRACK { = bdepth - bdepth 1 } {}
                ? > bdepth 0 { ( nurl_lex_advance lex ) } {}
            }
            : i tend ( nurl_lex_cur_start lex )  // at ']'
            : s ttext ( nurl_lex_src_slice lex tstart - tend tstart )
            ( nurl_lex_advance lex )  // consume ']'

            : i chstart ( nurl_lex_cur_start lex )
            : ~ i pdepth 0
            ~ | != ( nurl_lex_type lex ) TT_ARROW != pdepth 0 {
                : i tt ( nurl_lex_type lex )
                ? == tt TT_EOF { ( die lex `expected -> in select case` ) } {}
                ? | == tt TT_LPAREN == tt TT_LBRACK { = pdepth + pdepth 1 } {}
                ? | == tt TT_RPAREN == tt TT_RBRACK { = pdepth - pdepth 1 } {}
                ( nurl_lex_advance lex )
            }
            : i chend ( nurl_lex_cur_start lex )  // at '→'
            : s chtext ( nurl_lex_src_slice lex chstart - chend chstart )
            ( nurl_lex_advance lex )  // consume '→'

            ? ! ( is_ident_tok ( nurl_lex_type lex ) )
            { ( die lex `expected binding name after -> in select case` ) } {}
            : s bind ( nurl_lex_val lex )
            ( nurl_lex_advance lex )  // consume binding name

            ? != ( nurl_lex_type lex ) TT_LBRACE
            { ( die lex `expected { body } in select case` ) } {}
            : i bstart ( nurl_lex_cur_start lex )
            ( skip_balanced lex )  // cur now sits just after the body's '}'
            : i bend ( nurl_lex_cur_start lex )
            : s btext ( nurl_lex_src_slice lex bstart - bend bstart )

            : s ctl_name ( nurl_str_cat3 `__` uid ( nurl_str_cat `ctl` ( nurl_str_int bidx ) ) )
            // The channel operand is READ inline (never let-bound to a
            // fresh `( Channel T )` local — that would move it under the
            // borrow checker, and a `( ch )` wrapper would lex as a
            // call). `: i CTL # i . <ch> ctl` binds only an i64, so no
            // move; chtext must be a simple read (identifier or a
            // parenthesised call), `. <ch> ctl` resolving its `ctl`
            // field. The poll's chan_try_recv reads it the same way.
            = ctl_decls ( nurl_str_cat ctl_decls
            ( nurl_str_cat4 `: i ` ctl_name ( nurl_str_cat3 ` # i . ` chtext ` ctl` ) `\n` ) )
            = arm_block ( nurl_str_cat arm_block
            ( nurl_str_cat4 `( chan_raw_arm ` ctl_name ( nurl_str_cat ` ` w_name ) ` )\n` ) )
            = disarm_block ( nurl_str_cat disarm_block
            ( nurl_str_cat4 `( chan_raw_disarm ` ctl_name ( nurl_str_cat ` ` w_name ) ` )\n` ) )

            // Readiness is fully type-erased (chan_raw_poll reads only
            // the queue length + closed flag), so the element type is
            // needed only for the chosen arm's chan_try_recv. poll:
            //   ? ! DONE {
            //     : i P ( chan_raw_poll CTL )       // 0 none / 1 value / 2 closed
            //     ? > P 0 { = DONE T : ?T bind ( chan_try_recv [T] ( CH ) ) <body> } {}
            //   } {}
            : s poll_name ( nurl_str_cat3 `__` uid ( nurl_str_cat `p` ( nurl_str_int bidx ) ) )
            : s recv_call ( nurl_str_cat4 `( chan_try_recv [` ttext `] ` ( nurl_str_cat chtext ` )` ) )
            : s decl ( nurl_str_cat4 `: ?` ttext ( nurl_str_cat3 ` ` bind ` ` ) recv_call )
            : s p_decl ( nurl_str_cat4 `: i ` poll_name ` ( chan_raw_poll ` ( nurl_str_cat ctl_name ` )` ) )
            : s fire ( nurl_str_cat4 `= ` done_name ( nurl_str_cat3 ` T ` decl ` ` ) btext )
            : s guard ( nurl_str_cat4 `? > ` poll_name ( nurl_str_cat3 ` 0 { ` fire ` } {}` ) `` )
            : s poll ( nurl_str_cat4 `? ! ` done_name
            ( nurl_str_cat4 ` { ` p_decl ( nurl_str_cat ` ` guard ) ` } {}\n` ) `` )
            = poll_block ( nurl_str_cat poll_block poll )
            = bidx + bidx 1
        } {
            // ── _ → { body }  (default / non-blocking) ──
            ? ! ( is_ident_tok ( nurl_lex_type lex ) )
            { ( die lex `select case must start with [T] or _` ) } {}
            ? != 0 has_default { ( die lex `select has more than one default (_) arm` ) } {}
            ( nurl_lex_advance lex )  // consume '_'
            ( expect lex TT_ARROW )
            ? != ( nurl_lex_type lex ) TT_LBRACE
            { ( die lex `expected { body } in select default` ) } {}
            : i dstart ( nurl_lex_cur_start lex )
            ( skip_balanced lex )
            : i dend ( nurl_lex_cur_start lex )
            = default_body ( nurl_lex_src_slice lex dstart - dend dstart )
            = has_default 1
        }
    }
    ( expect lex TT_RBRACE )  // consume select's closing '}'

    ? == bidx 0 { ( die lex `select has no channel cases` ) } {}

    // ── Assemble the synthesised source ──
    : ~ s src `{\n`
    = src ( nurl_str_cat src ctl_decls )
    = src ( nurl_str_cat4 src `: ~ b ` done_name ` F\n` )
    ? != 0 has_default {
        // Non-blocking: poll once, then default.
        = src ( nurl_str_cat src poll_block )
        : s dhead ( nurl_str_cat3 `? ! ` done_name ` { ` )
        : s dtail ( nurl_str_cat3 ` = ` done_name ` T } {}\n` )
        = src ( nurl_str_cat4 src dhead default_body dtail )
    } {
        // Blocking: arm / poll / wait / disarm loop.
        = src ( nurl_str_cat4 src `: i ` w_name ` ( select_waiter_new )\n` )
        = src ( nurl_str_cat4 src `~ ! ` done_name ` {\n` )
        = src ( nurl_str_cat4 src `( select_waiter_prepare ` w_name ` )\n` )
        = src ( nurl_str_cat src arm_block )
        = src ( nurl_str_cat src poll_block )
        = src ( nurl_str_cat4 src ( nurl_str_cat3 `? ! ` done_name ` { ( select_waiter_wait ` )
        ( nurl_str_cat3 w_name ` )` ` } {}\n` ) `` )
        = src ( nurl_str_cat src disarm_block )
        = src ( nurl_str_cat src `}\n` )
        = src ( nurl_str_cat4 src `( select_waiter_free ` w_name ` )\n` )
    }
    = src ( nurl_str_cat src `}\n` )

    // ── Compile the synthesised block through a sub-lexer ──
    : i sub ( nurl_lex_new src `<select>` )
    ( gen_stmt sub syms cg )
    ( nurl_set_last_type `void` )
    ^ ``
}

// emit_or_chain: lower the alternatives of an or-pattern `A | B | C →`.
// `tag_reg` holds the scrutinee's i64 variant tag. Starting at
// `first_label`, each alternative loads its variant tag constant,
// compares, and branches to `tag_ok_label` (the arm body) on a match or
// to the next alternative — the last falling through to `next_label`.
@ emit_or_chain i cg s tag_reg s or_names s tag_ok_label s next_label s first_label → v {
    : ~ s rest or_names
    : ~ s cur_lbl first_label
    ~ != 0 ( nurl_str_len rest ) {
        : s vname ( str_first_word rest )
        = rest ( str_skip_word rest )
        : b is_last == 0 ( nurl_str_len rest )
        : s miss_lbl ? is_last next_label ( nurl_cg_lbl cg `oralt` )
        ( nurl_print cur_lbl ) ( nurl_print `:\n` )
        : s c ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print c )
        ( nurl_print ` = load i64, i64* @` ) ( nurl_print vname ) ( nurl_print `\n` )
        : s m ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print m )
        ( nurl_print ` = icmp eq i64 ` ) ( nurl_print tag_reg )
        ( nurl_print `, ` ) ( nurl_print c ) ( nurl_print `\n` )
        ( nurl_print `  br i1 ` ) ( nurl_print m )
        ( nurl_print `, label %` ) ( nurl_print tag_ok_label )
        ( nurl_print `, label %` ) ( nurl_print miss_lbl ) ( emit_dbg_eol )
        = cur_lbl miss_lbl
    }
}

@ gen_match i lex i syms i cg → s {
    // Borrow checker (Phase 0d): source line of the `??`, for the
    // `match`/`endmatch` structural markers bracketing this match.
    : i bck_mline ( nurl_lex_line lex )
    ( nurl_lex_advance lex )  // consume '??'

    // `?? {` (no scrutinee) is a Go-style channel select, not a match.
    ? == ( nurl_lex_type lex ) TT_LBRACE { ^ ( gen_select lex syms cg ) } {}

    // Peek the variable name (if any) BEFORE gen_expr consumes it, so we
    // can later look up `<name>__res_nurl_T` (set by gen_let_or_struct)
    // to know the source-level NURL T of an `! T E` value being matched.
    : ~ s match_var_name ? ( is_ident_tok ( nurl_lex_type lex ) ) ( nurl_lex_val lex ) ``

    // Generate the value to match against. Clear __last_nurl_call__
    // first: for a non-binding scrutinee, a non-empty value afterwards
    // means the scrutinee's outermost operation was a call, and the
    // value is that callee's NURL return type (`! T E`).
    ( nurl_sym_def syms `__last_nurl_call__` `` )
    ( nurl_sym_def syms `__last_call_res_t_llvm__` `` )
    ( nurl_sym_def syms `__last_call_res_e_llvm__` `` )
    ( nurl_sym_def syms `__last_call_opt_nurl_t__` `` )
    : s match_val ( gen_operand lex syms cg )
    : s match_type ( nurl_get_last_type )
    // Borrow provenance: snapshot whether the SCRUTINEE was a borrow. A
    // match that yields a value out of a borrowed scrutinee conservatively
    // yields a borrow (the arms commonly return a payload view); restored
    // onto __last_value_borrow__ at every return below so a `^ ?? …` makes
    // the function ret_borrow. (Only consequential for auto-Drop enums.)
    : s match_scrut_borrow ( nurl_sym_get syms `__last_value_borrow__` )

    // A `?? ( f … )` whose scrutinee is a direct call has no binding
    // name, so the payload metadata below (keyed on `<name>__res_nurl_T`
    // / `__res_t_llvm` for `! T E`, and `<name>__opt_nurl_T` for `? T`)
    // would be skipped — a wide / handle / pointer payload would be read
    // as its raw i64 slot, and an unsigned `? u` payload would drop its
    // signedness flag (silent garbage / wrong sign-extension). Synthesise
    // a binding name and populate those keys from the callee's return
    // type so the direct-call form behaves identically to `?? r`.
    : s mcall_nurl ( nurl_sym_get syms `__last_nurl_call__` )
    : s mcall_opt_t ( nurl_sym_get syms `__last_call_opt_nurl_t__` )
    ? & == 0 ( nurl_str_len match_var_name )
    | != 0 ( nurl_str_len mcall_nurl ) != 0 ( nurl_str_len mcall_opt_t )
    { : s msynth ( nurl_str_cat `__matchtmp` ( nurl_cg_lbl cg `mt` ) )
        // `! T E` callee: reconstruct T (and E) payloads.
        ? != 0 ( nurl_str_len mcall_nurl )
        { : s minner_t ( str_first_word ( str_skip_word mcall_nurl ) )
            : s minner_e ( str_first_word ( str_skip_word ( str_skip_word mcall_nurl ) ) )
            ( nurl_sym_def syms ( nurl_str_cat msynth `__res_nurl_T` ) minner_t )
            ( nurl_sym_def syms ( nurl_str_cat msynth `__res_nurl_E` ) minner_e )
            // LLVM type of T: prefer the callee's pre-computed `__res_t_llvm`
            // (correct for paren-compound handles `( Vec u )` → `%Vec__i8`
            // AND pointer payloads `s` → `i8*`, neither of which
            // `nurl_sym_get syms minner_t` can resolve). Fall back to the
            // by-name struct lookup when the side-channel is empty.
            : ~ s minner_llvm ( nurl_sym_get syms `__last_call_res_t_llvm__` )
            ? == 0 ( nurl_str_len minner_llvm ) { = minner_llvm ( nurl_sym_get syms minner_t ) } {}
            ? != 0 ( nurl_str_len minner_llvm )
            { ( nurl_sym_def syms ( nurl_str_cat msynth `__res_t_llvm` ) minner_llvm ) }
            {}
            // Same for the Err-payload E's LLVM type, so an `F e → e` arm
            // whose E is a bare pointer reconstructs too (enum E resolves
            // by name).
            : s minner_e_llvm ( nurl_sym_get syms `__last_call_res_e_llvm__` )
            ? != 0 ( nurl_str_len minner_e_llvm )
            { ( nurl_sym_def syms ( nurl_str_cat msynth `__res_e_llvm` ) minner_e_llvm ) }
            {} }
        {}
        // `? T` callee: carry the inner NURL type token so the T-arm
        // payload binding propagates the unsigned flag (`? u` / `? u16`
        // / …). Without this a `# i b` widen on the bound byte sign-
        // extends (0x86 → -122) instead of zero-extending. Mirrors
        // gen_let_or_struct's `<name>__opt_nurl_T` for `?? r`.
        ? != 0 ( nurl_str_len mcall_opt_t )
        { ( nurl_sym_def syms ( nurl_str_cat msynth `__opt_nurl_T` ) mcall_opt_t ) }
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
    : ~ s seen_variants ``
    : ~ i has_wildcard 0

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
            // A BOOL pattern (`T` / `F`) matches an Option (`? T`) or Result
            // (`! T E`): the T-arm binds the single value / Ok-payload, the
            // F-arm binds the error (or nothing). Either way at most ONE slot.
            : b is_bool_pat == pat_tt TT_BOOL
            // For an integer-literal pattern normalise the spelling so a
            // `0x…` / `0b…` literal doesn't reach the `icmp` constant as
            // raw text (LLVM would read `0x…` as a hex float). Decimal
            // text passes through unchanged.
            : s pattern_name ? is_int_pat ( __norm_int_lit ( nurl_lex_val lex ) ) ( nurl_lex_val lex )
            ( nurl_lex_advance lex )

            // Or-patterns: `A | B | C → body`. Several tag-only variants
            // share one body. Collected here as a space-separated list
            // of the EXTRA names (pattern_name is the first). Restricted
            // to named variants with no payload + no literal constraint —
            // the alternatives would bind different payload shapes, so
            // only the tag is compared.
            : ~ s or_names ``
            ? ! is_int_pat
            { ~ == ( nurl_lex_type lex ) TT_PIPE {
                    ( nurl_lex_advance lex )  // consume '|'
                    ? ( is_ident_tok ( nurl_lex_type lex ) )
                    { = or_names ? == 0 ( nurl_str_len or_names )
                        ( nurl_lex_val lex )
                        ( nurl_str_cat3 or_names ` ` ( nurl_lex_val lex ) )
                        ( nurl_lex_advance lex ) }
                    { ( die lex `expected variant name after '|' in or-pattern` ) }
                } }
            {}
            : b has_or != 0 ( nurl_str_len or_names )

            // Collect up to 3 payload slots before the arrow.  Each slot is either
            // an identifier (binds the payload) or an integer literal (compared).
            // Int-literal patterns carry no payload — skip the loop entirely.
            : ~ s pv0 ``
            : ~ s pv1 ``
            : ~ s pv2 ``
            : ~ s pv_over ``
            : ~ s lit0 ``
            : ~ s lit1 ``
            : ~ s lit2 ``
            : ~ s lit_over ``
            : ~ i over_has_lit 0
            : ~ i pvc 0
            ~ & & ! is_int_pat != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_QUEST {
                : i pst ( nurl_lex_type lex )
                ? ( is_ident_tok pst ) {
                    ? == pvc 0 { = pv0 ( nurl_lex_val lex ) } {}
                    ? == pvc 1 { = pv1 ( nurl_lex_val lex ) } {}
                    ? == pvc 2 { = pv2 ( nurl_lex_val lex ) } {}
                    ? >= pvc 3 {
                        = pv_over ? == 0 ( nurl_str_len pv_over ) ( nurl_lex_val lex ) ( nurl_str_cat3 pv_over ` ` ( nurl_lex_val lex ) )
                        = lit_over ? == 0 ( nurl_str_len lit_over ) `_` ( nurl_str_cat lit_over ` _` )
                    } {}
                    = pvc + pvc 1
                    ( nurl_lex_advance lex )
                } {
                    ? == pst TT_INT {
                        // Normalise so a `0x…` / `0b…` field-constraint
                        // reaches the IR as decimal, not raw hex text.
                        : s ival ( __norm_int_lit ( nurl_lex_val lex ) )
                        ? == pvc 0 { = lit0 ival } {}
                        ? == pvc 1 { = lit1 ival } {}
                        ? == pvc 2 { = lit2 ival } {}
                        ? >= pvc 3 {
                            = lit_over ? == 0 ( nurl_str_len lit_over ) ival ( nurl_str_cat3 lit_over ` ` ival )
                            = pv_over ? == 0 ( nurl_str_len pv_over ) `_` ( nurl_str_cat pv_over ` _` )
                            = over_has_lit 1
                        } {}
                        = pvc + pvc 1
                        ( nurl_lex_advance lex )
                    } {
                        ( die lex `expected arrow or payload variable` )
                    }
                }
            }
            : b has_lit | | | != 0 ( nurl_str_len lit0 )
            != 0 ( nurl_str_len lit1 )
            != 0 ( nurl_str_len lit2 )
            != 0 over_has_lit

            // Payload-arity check (critic A7, ghost-variant half). When
            // the pattern names a DECLARED enum variant (it has a
            // `__paycount` record — `T`/`F` result/option arms and
            // wildcards don't), binding more slots than the variant
            // declares would emit an out-of-bounds extractvalue: either
            // invalid IR (clang rejects far from the cause) or, when a
            // SIBLING variant's payload slot exists, a silent garbage
            // read. The classic trigger is a payload TYPE name in the
            // enum declaration that wasn't defined/imported — the
            // parser then reads it as a separate variant and the
            // intended payload silently vanishes.
            : s __pc_s ( nurl_sym_get syms ( nurl_str_cat pattern_name `__paycount` ) )
            ? & != 0 ( nurl_str_len __pc_s ) > pvc ( nurl_str_to_int __pc_s )
            { ( die lex ( nurl_str_cat3
                ( nurl_str_cat3 `match arm binds ` ( nurl_str_int pvc ) ` payload(s) but variant '` )
                pattern_name
                ( nurl_str_cat3 `' declares only ` __pc_s ` — if a CamelCase name in the enum declaration was meant as this variant's payload TYPE, note that an unknown/unimported type name parses as a SEPARATE variant; define or import the type before the enum.` ) ) ) }
            {}
            // Option / Result T-or-F arm: at most one payload slot. Binding
            // more (`?? o { T a b → … }`) used to emit an out-of-range
            // `extractvalue { i1, T } v, 2` that only clang/llvm-as rejected.
            ? & is_bool_pat > pvc 1
            { ( die lex ( nurl_str_cat
                ( nurl_str_cat3 `match arm binds ` ( nurl_str_int pvc ) ` payloads but an option/result '` )
                ( nurl_str_cat pattern_name `' arm binds at most one (the T-arm value / Ok payload, or the F-arm error)` ) ) ) }
            {}
            // Payload binding requires an aggregate scrutinee — an enum (`%E`)
            // or an option / result (`{ i1, … }`). Binding a payload while
            // matching a non-aggregate scalar (`?? n { T a → … }` with `n : i`)
            // emitted an `extractvalue` on the scalar that only clang/llvm-as
            // rejected. Integer-literal arms (no payload) and bare tag matches
            // (pvc 0) are unaffected.
            ? > pvc 0
            { ? != 0 ( nurl_str_len match_type )
                { ? & != ( nurl_str_get match_type 0 ) 37 != ( nurl_str_get match_type 0 ) 123
                    { ( die lex ( nurl_str_cat3 `cannot bind a payload when matching the non-aggregate type '` ( llvm_to_nurl match_type ) `' — only an enum, option, or result carries payloads` ) ) }
                    {} }
                {} }
            {}

            // Optional guard: `Pattern payloads ? <cond> → body`. The
            // guard is evaluated AFTER payload binding (so it can read
            // the bound payloads) — a false guard falls through to the
            // next arm. Record its source position now and skip it; it
            // is replayed at the arm body via set_pos.
            : ~ i has_guard 0
            : ~ i guard_pos 0
            ? == ( nurl_lex_type lex ) TT_QUEST {
                = has_guard 1
                ( nurl_lex_advance lex )  // consume '?'
                = guard_pos ( nurl_lex_cur_start lex )
                : ~ i gd 0
                ~ | != ( nurl_lex_type lex ) TT_ARROW != gd 0 {
                    : i gt ( nurl_lex_type lex )
                    ? == gt TT_EOF { ( die lex `expected -> after match guard` ) } {}
                    ? | == gt TT_LPAREN == gt TT_LBRACK { = gd + gd 1 } {}
                    ? | == gt TT_RPAREN == gt TT_RBRACK { = gd - gd 1 } {}
                    ( nurl_lex_advance lex )
                }
            } {}

            ( expect lex TT_ARROW )  // expect '→'
            : i body_pos ( nurl_lex_cur_start lex )

            // Generate arm label; wildcard skips comparison and jumps directly
            : s arm_label ( nurl_cg_lbl cg `arm` )
            : ~ s next_label ``
            // Guards need a `next_label` to fall through to on a false
            // guard; a wildcard arm has none (and a guarded catch-all is
            // a contradiction anyway). Or-patterns + guards are kept
            // orthogonal for v1.
            ? & != 0 has_guard ( seq pattern_name `_` )
            { ( die lex `a guard (? cond) on a wildcard arm is not supported - guard a specific pattern instead` ) } {}
            ? & != 0 has_guard has_or
            { ( die lex `cannot combine an or-pattern with a guard` ) } {}
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
                    ( nurl_print ` = icmp eq ` ) ( nurl_print ( nurl_llty match_type ) )
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
                    // A guarded arm does NOT cover its variant for
                    // exhaustiveness (the guard may be false) — same as a
                    // literal-constrained arm.
                    ? | has_lit != 0 has_guard {} {
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
                    // (`: ~ *T` mutable-pointer binding.)
                    : b match_is_bare_tag | ( seq match_type `i1` ) == ( int_width match_type ) 64
                    : s tag_reg ? match_is_bare_tag match_val ( nurl_cg_reg cg )
                    ? match_is_bare_tag {} {
                        ( nurl_print `  ` ) ( nurl_print tag_reg )
                        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty match_type ) )
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

                    // Or-pattern bookkeeping (tag-only; no payload, no
                    // literal, named variants only). Record every
                    // alternative for exhaustiveness + duplicate checks.
                    ? has_or {
                        ? != 0 pvc { ( die lex `or-pattern variants cannot bind payloads` ) } {}
                        ? has_lit { ( die lex `or-pattern cannot mix literal constraints` ) } {}
                        ? is_bool_pat { ( die lex `or-pattern applies to named enum variants, not T/F` ) } {}
                        : ~ s orr or_names
                        ~ != 0 ( nurl_str_len orr ) {
                            : s vn ( str_first_word orr )
                            = orr ( str_skip_word orr )
                            ? ( str_contains_word seen_variants vn )
                            { ( die lex ( nurl_str_cat `duplicate match arm for variant: ` vn ) ) } {}
                            = seen_variants ? == 0 ( nurl_str_len seen_variants )
                            vn ( nurl_str_cat3 seen_variants ` ` vn )
                        }
                    } {}

                    = next_label ( nurl_cg_lbl cg `next` )
                    // If the pattern has literal constraints, jump to a literal-check
                    // block first; otherwise branch straight to the arm body.
                    : s tag_ok_label ? has_lit ( nurl_cg_lbl cg `litchk` ) arm_label
                    // On a first-variant miss: an or-pattern falls through
                    // its alternative chain; a plain arm goes to next_label.
                    : s first_miss ? has_or ( nurl_cg_lbl cg `oralt` ) next_label
                    ( nurl_print `  br i1 ` ) ( nurl_print cmp_reg )
                    ( nurl_print `, label %` ) ( nurl_print tag_ok_label )
                    ( nurl_print `, label %` ) ( nurl_print first_miss ) ( emit_dbg_eol )
                    // Or-pattern alternatives: compare the tag to each
                    // further variant; any match jumps to the arm body.
                    ? has_or
                    { ( emit_or_chain cg tag_reg or_names tag_ok_label next_label first_miss ) }
                    {}
                    // Emit chained literal comparisons.  Each failure jumps to next_label;
                    // the last successful check falls through to arm_label.
                    ? has_lit {
                        ( nurl_print tag_ok_label ) ( nurl_print `:\n` )
                        ( emit_lit_check cg syms match_val match_type pattern_name 0 lit0 next_label )
                        ( emit_lit_check cg syms match_val match_type pattern_name 1 lit1 next_label )
                        ( emit_lit_check cg syms match_val match_type pattern_name 2 lit2 next_label )
                        // Literal constraints on payload slots 3+ (rare).
                        : ~ s lc_rest lit_over
                        : ~ i lc_idx 3
                        ~ != 0 ( nurl_str_len lc_rest ) {
                            : s lc_tok ( str_first_word lc_rest )
                            = lc_rest ( str_skip_word lc_rest )
                            ? ! ( seq lc_tok `_` ) { ( emit_lit_check cg syms match_val match_type pattern_name lc_idx lc_tok next_label ) } {}
                            = lc_idx + lc_idx 1
                        }
                        ( nurl_print `  br label %` ) ( nurl_print arm_label ) ( emit_dbg_eol )
                    } {}
                } }

            // Generate the arm code
            ( nurl_print arm_label ) ( nurl_print `:\n` )
            ( nurl_sym_def syms `__cur_lbl__` arm_label )
            // Scope each match arm so payload bindings and owned-string entries
            // don't leak into sibling arms (see gen_cond for the same reasoning).
            : ~ s old_strs_m ``
            : ~ s old_structs_m ``
            : ~ s old_user_m ``
            : ~ s old_closure_m ( nurl_sym_get syms `__owned_closure_envs__` )
            ? != 0 g_auto_drop_strings
            { = old_strs_m ( nurl_sym_get syms `__owned_strings__` )
                = old_structs_m ( nurl_sym_get syms `__owned_struct_fields__` )
                = old_user_m ( nurl_sym_get syms `__user_drops__` )
                ( nurl_sym_push syms )
            } {}

            // Bind first payload variable (enum field 1)
            ? != 0 ( nurl_str_len pv0 ) {
                : ~ s pt0 ( nurl_sym_get syms ( nurl_str_cat pattern_name `__payload__0` ) )
                // Bool patterns (T/F) on opt/res have no symbol entry — the payload
                // type lives inside match_type as `{ i1, X }`. Strip the `{ i1, `
                // prefix and ` }` suffix to recover X. Unlike named-enum variants
                // whose payload is stored as opaque ptr, opt/res field 1 is already
                // stored at its real type, so no ptr→X conversion is required.
                : ~ b pt0_is_opt_bool F
                // Result (`{ i1, T, E }`, 3-field): the Ok arm (`T`) binds field
                // 1 (type T), the Err arm (`F`) binds field 2 (type E), each BY
                // VALUE at its real type — no i64 reconstruction. Option
                // (`{ i1, T }`, 2-field) keeps field-1-by-value.
                : b match_is_res & & >= ( nurl_str_len match_type ) 6
                ( seq ( nurl_str_slice match_type 0 6 ) `{ i1, ` )
                == ( agg_field_count syms match_type ) 3
                : i res_fidx ? & match_is_res ( seq pattern_name `F` ) 2 1
                ? & == 0 ( nurl_str_len pt0 )
                & | ( seq pattern_name `T` ) ( seq pattern_name `F` )
                & >= ( nurl_str_len match_type ) 6
                ( seq ( nurl_str_slice match_type 0 6 ) `{ i1, ` )
                { ? match_is_res
                    { = pt0 ( compound_field_type match_type res_fidx ) }
                    { = pt0 ( nurl_str_slice match_type 6 - ( nurl_str_len match_type ) 8 ) }
                    = pt0_is_opt_bool T }
                {}
                : s pr0 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print pr0 )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty match_type ) )
                ( nurl_print ` ` ) ( nurl_print match_val )
                ( nurl_print `, ` ) ( nurl_print ( nurl_str_int res_fidx ) ) ( nurl_print `\n` )
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
                // The legacy i64-unbox reconstruction only applies to the old
                // `{ i1, i64 }` result squeeze; a wide `{ i1, T, E }` result is
                // already extracted by value above, so skip it (`! match_is_res`).
                // Option still needs the f→bitcast / b→trunc / handle-rebuild here.
                ? & & pt0_is_opt_bool ! match_is_res != 0 ( nurl_str_len match_var_name )
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
                    // `b` (bool) source type with an i64 payload slot: the bool
                    // rode the slot widened to i64, so truncate back to i1 — a
                    // `! b E` Ok-payload (or `? b` Some-payload) must materialise
                    // as i1 so the binding and its `!`/`&`/`|` uses type-check.
                    // Without this the var is stored/loaded as i64 while `! b`
                    // emits `xor i1`, which clang rejects. The inner NURL type is
                    // `__res_nurl_T` for results and `__opt_nurl_T` for options.
                    : s bopt_t ( nurl_sym_get syms ( nurl_str_cat match_var_name `__opt_nurl_T` ) )
                    ? & ( seq pt0 `i64` ) | ( seq nurl_inner_t `b` ) ( seq bopt_t `b` )
                    { : s bl_uc ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print bl_uc )
                        ( nurl_print ` = trunc i64 ` ) ( nurl_print pr0 )
                        ( nurl_print ` to i1\n` )
                        = pt0_eff `i1`
                        = pr0_eff bl_uc
                        = did_reconstruct T
                    } {}
                    ? != 0 ( nurl_str_len nurl_inner_t )
                    { : ~ s nurl_inner_llvm ( nurl_sym_get syms nurl_inner_t )
                        // Fallback for paren-compound T (e.g. `( Vec u )`):
                        // `nurl_inner_t` was the literal `(` token from
                        // parse_type_res's `nurl_lex_val`-before-parse capture,
                        // which doesn't look up to anything. Use the saved
                        // LLVM type instead. T uses `__res_t_llvm`, F uses
                        // `__res_e_llvm`. Enum error types (NetErr/WsErr/…)
                        // resolve via their single-token NURL name above and
                        // never reach this fallback; it only fills the gap for
                        // pointer / paren-compound payloads.
                        ? & == 0 ( nurl_str_len nurl_inner_llvm ) ( seq pattern_name `T` )
                        { = nurl_inner_llvm ( nurl_sym_get syms ( nurl_str_cat match_var_name `__res_t_llvm` ) ) }
                        {}
                        ? & == 0 ( nurl_str_len nurl_inner_llvm ) ( seq pattern_name `F` )
                        { = nurl_inner_llvm ( nurl_sym_get syms ( nurl_str_cat match_var_name `__res_e_llvm` ) ) }
                        {}
                        // Raw-pointer payload — ANY LLVM type ending in `*`,
                        // whether `i8*` (bare `s`) or `%Struct*` (a NURL
                        // `*Struct` pointer). The i64 slot holds the pointer
                        // via ptrtoint, so one inttoptr recovers it. The
                        // trailing `*` is the reliable discriminator from the
                        // `%`-struct-HANDLE branch below (e.g. `%Vec__i8`,
                        // `%String` — handles never end in `*`). Routing on the
                        // leading `%` instead used to misclassify `%Struct*`
                        // pointers as handles: the struct path looked up
                        // `Struct*__idx_0__type`, found nothing, reconstructed
                        // nothing, and the binding got the raw i64 slot as
                        // garbage (the `! *T E` pointer-unwrap miscompile).
                        ? & != 0 ( nurl_str_len nurl_inner_llvm )
                        == ( nurl_str_get nurl_inner_llvm - ( nurl_str_len nurl_inner_llvm ) 1 ) 42
                        { : s ptv_r ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print ptv_r )
                            ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 )
                            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) ) ( nurl_print `\n` )
                            = pt0_eff nurl_inner_llvm
                            = pr0_eff ptv_r
                            = did_reconstruct T }
                        {}
                        ? & & != 0 ( nurl_str_len nurl_inner_llvm )
                        == ( nurl_str_get nurl_inner_llvm 0 ) 37
                        != ( nurl_str_get nurl_inner_llvm - ( nurl_str_len nurl_inner_llvm ) 1 ) 42
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
                                : s ni_fc ( nurl_sym_get syms ( nurl_str_cat sname_r `__field_count` ) )
                                : b ni_single & != 0 ( nurl_str_len ni_fc ) == ( nurl_str_to_int ni_fc ) 1
                                : b ni_f0_is_ptr & != 0 ( nurl_str_len ni_f0_ty )
                                == ( nurl_str_get ni_f0_ty - ( nurl_str_len ni_f0_ty ) 1 ) 42
                                ? & ni_single ni_f0_is_ptr
                                { : s pcv_r ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print pcv_r )
                                    ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 )
                                    ( nurl_print ` to ` ) ( nurl_print ( nurl_llty ni_f0_ty ) ) ( nurl_print `\n` )
                                    : s sv_r ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print sv_r )
                                    ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) )
                                    ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty ni_f0_ty ) )
                                    ( nurl_print ` ` ) ( nurl_print pcv_r ) ( nurl_print `, 0\n` )
                                    = pt0_eff nurl_inner_llvm
                                    = pr0_eff sv_r
                                    = did_reconstruct T }
                                ? != 0 ( nurl_str_len ni_f0_ty )
                                {  // Heap-box multi-field struct: load + free.
                                    : s ubp_s ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubp_s )
                                    ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 )
                                    ( nurl_print ` to ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) ) ( nurl_print `*\n` )
                                    : s ubv_s ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubv_s )
                                    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) )
                                    ( nurl_print `, ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) )
                                    ( nurl_print `* ` ) ( nurl_print ubp_s ) ( nurl_print `\n` )
                                    : s ubraw_s ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubraw_s )
                                    ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) )
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
                                    ( nurl_print ` to ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) ) ( nurl_print `*\n` )
                                    : s ubv ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubv )
                                    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) )
                                    ( nurl_print `, ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) )
                                    ( nurl_print `* ` ) ( nurl_print ubp ) ( nurl_print `\n` )
                                    : s ubraw ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print ubraw )
                                    ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty nurl_inner_llvm ) )
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
                    ? ( is_float_ty pt0 )
                    { ( emit_enum_float_extract cv0 pt0 pr0 cg ) }
                    { ? & > ( int_width pt0 ) 0 < ( int_width pt0 ) 64 {
                            // Narrow integer payload (i1 / i8 / i16 / i32, incl.
                            // the unsigned u/u16/u32): the value rode the i64 slot
                            // widened (gen_agg_lit) — trunc to the payload's width.
                            // Signedness for a later widen is set on the binding
                            // below.
                            ( nurl_print `  ` ) ( nurl_print cv0 )
                            ( nurl_print ` = trunc i64 ` ) ( nurl_print pr0 ) ( nurl_print ` to ` ) ( nurl_print ( nurl_llty pt0 ) ) ( nurl_print `\n` )
                        } {
                            // Struct-handle payload (e.g. %Vec__Json, %String): the
                            // i64 slot holds the struct's field-0 pointer (aggregate
                            // construction does the inverse — extractvalue 0 +
                            // ptrtoint into the i64 slot). inttoptr it back and
                            // reconstruct by insertvalue.
                            : ~ b pt0_is_struct_handle F
                            : ~ s pt0_f0_ty ``
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
                            { : s h0p ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print h0p )
                                ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 )
                                ( nurl_print ` to ` ) ( nurl_print ( nurl_llty pt0_f0_ty ) ) ( nurl_print `\n` )
                                ( nurl_print `  ` ) ( nurl_print cv0 )
                                ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty pt0 ) )
                                ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty pt0_f0_ty ) )
                                ( nurl_print ` ` ) ( nurl_print h0p ) ( nurl_print `, 0\n` ) }
                            { ? | == ( nurl_str_get pt0 0 ) 123
                                & == ( nurl_str_get pt0 0 ) 37
                                != ( nurl_str_get pt0 - ( nurl_str_len pt0 ) 1 ) 42
                                {  // Anonymous aggregate (`{ i1, i64 }`) OR a named
                                    // non-pointer type (`%Geom` multi-field struct /
                                    // `%Color` enum) — the i64 slot holds a heap-box
                                    // pointer to the whole value (see the symmetric
                                    // heap-box in gen_agg_lit's enum-construction
                                    // path). inttoptr + load the value back. A
                                    // pointer payload (`%Ast*`) keeps the inttoptr
                                    // fallthrough below — the slot holds the pointer
                                    // itself, not a box.
                                    : s b0p ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print b0p )
                                    ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 ) ( nurl_print ` to ptr\n` )
                                    ( nurl_print `  ` ) ( nurl_print cv0 )
                                    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty pt0 ) )
                                    ( nurl_print `, ptr ` ) ( nurl_print b0p ) ( nurl_print `\n` )
                                }
                                { ( nurl_print `  ` ) ( nurl_print cv0 )
                                    ? == ( int_width pt0 ) 64
                                    { ( nurl_print ` = add i64 ` ) ( nurl_print pr0 ) ( nurl_print `, 0\n` ) }
                                    { ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr0 ) ( nurl_print ` to i8*\n` ) } } }
                        }
                    }
                }
                : s vp0 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print vp0 )
                ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty pt0_eff ) ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty pt0_eff ) )
                ( nurl_print ` ` ) ( nurl_print cv0 )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt0_eff ) )
                ( nurl_print `* ` ) ( nurl_print vp0 ) ( nurl_print `\n` )
                // pt0_eff is the raw internal payload type (`u8` distinct
                // from `i8` since A1), so the binding carries the
                // payload's signedness in its type and a later `# i <b>`
                // widen zero-extends a `u`-family payload.
                ( nurl_sym_def syms pv0 pt0_eff )
                ( nurl_sym_def syms ( nurl_str_cat pv0 `__ptr` ) vp0 )
                // Phase 2D: a match-arm payload binding OWNS its value just
                // like a `:` let, so a `% Drop` impl on the payload type must
                // fire at arm scope exit. Register it here (mirrors gen_let's
                // user-drop registration) so an unwrapped `! Database E` /
                // `? Statement` handle auto-closes without a manual call even
                // on the Err / early-exit paths. Skipped if the value escapes
                // the arm (mem_drop_new_user_drops only fires on a void arm).
                ? != 0 g_auto_drop_strings
                { : s arm_impl_key ( nurl_str_cat `drop##` pt0_eff )
                    : s arm_impl_mangle ( nurl_sym_get g_impl_name_syms arm_impl_key )
                    // Skip COMPILER-auto drops on a match-arm payload — it is
                    // commonly a borrow (vec_get / accessor); only a user
                    // `% Drop` consumes its arm payload.
                    ? & != 0 ( nurl_str_len arm_impl_mangle )
                    == 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms ( nurl_str_cat `autodrop##` pt0_eff ) ) )
                    { ( mem_own_add_user_drop syms vp0 pt0_eff ) }
                    {}
                }
                {}
                // Borrow provenance: a match-arm payload of an auto-Drop
                // enum is a VIEW into the matched value (a borrow) — mark it
                // so a `^ payload` return propagates ret_borrow.
                ? ( __is_autodrop_enum pt0_eff syms )
                { ( nurl_sym_def syms ( nurl_str_cat pv0 `__borrow` ) `1` ) }
                {}
                // Unsigned `?u` / `?u16` / `?u32` / `?u64` and `! u64 E`
                // matches: the arm binding's TYPE must keep the unsigned
                // spelling (same width, so the alloca above is
                // unaffected). Reconstruction paths that rebuilt the
                // payload width-wise may have produced the signed
                // spelling — upgrade it from the recorded NURL inner
                // type. Without this a downstream `# i b` cast in the
                // arm body emits sext instead of zext for high-bit-set
                // bytes (bit us in bytes_to_hex over SHA-1 digests), and
                // `?? r { T v → … }` over an `! u64 E` picked srem/sdiv.
                ? & pt0_is_opt_bool & ( seq pattern_name `T` ) != 0 ( nurl_str_len match_var_name )
                { : s opt_t ( nurl_sym_get syms ( nurl_str_cat match_var_name `__opt_nurl_T` ) )
                    : s res_t ( nurl_sym_get syms ( nurl_str_cat match_var_name `__res_nurl_T` ) )
                    ? | ( nurl_type_is_unsigned opt_t ) ( nurl_type_is_unsigned res_t )
                    { ( nurl_sym_def syms pv0 ( ty_to_unsigned pt0_eff ) ) }
                    {} }
                {}
                // The Err arm (`F e`) of `! T E` binds the ERROR payload E —
                // same spelling upgrade via `__res_nurl_E` (set by
                // gen_let_or_struct / the direct-call synthesis). Without
                // this `?? r { F e → % e 10 }` over an `! T u64` treated
                // e as signed.
                ? & pt0_is_opt_bool & ( seq pattern_name `F` ) != 0 ( nurl_str_len match_var_name )
                { : s res_e ( nurl_sym_get syms ( nurl_str_cat match_var_name `__res_nurl_E` ) )
                    ? ( nurl_type_is_unsigned res_e )
                    { ( nurl_sym_def syms pv0 ( ty_to_unsigned pt0_eff ) ) }
                    {} }
                {}
            } {}
            // Bind second payload variable (enum field 2)
            ? != 0 ( nurl_str_len pv1 ) {
                : s pt1 ( nurl_sym_get syms ( nurl_str_cat pattern_name `__payload__1` ) )
                : s pr1 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print pr1 )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty match_type ) )
                ( nurl_print ` ` ) ( nurl_print match_val ) ( nurl_print `, 2\n` )
                : s cv1 ( nurl_cg_reg cg )
                ? ( is_float_ty pt1 )
                { ( emit_enum_float_extract cv1 pt1 pr1 cg ) }
                { ? & > ( int_width pt1 ) 0 < ( int_width pt1 ) 64 {
                        ( nurl_print `  ` ) ( nurl_print cv1 )
                        ( nurl_print ` = trunc i64 ` ) ( nurl_print pr1 ) ( nurl_print ` to ` ) ( nurl_print ( nurl_llty pt1 ) ) ( nurl_print `\n` )
                    } {
                        // Mirror slot-0 reconstruction (the inverse of
                        // gen_agg_lit's enum-construction boxing). A `%`-named
                        // payload is either a single-pointer handle (Vec/String/…:
                        // f0 is a pointer, stashed bare → rebuild via insertvalue)
                        // or a multi-field struct / enum / anon aggregate (heap-
                        // boxed → load through the box pointer). Without this,
                        // slots 1-2 fell straight to the i8* bitcast and stored a
                        // `ptr` into a `%Struct` slot (clang reject — the
                        // non-slot-0 struct-payload hole).
                        : ~ b pt1_is_struct_handle F
                        : ~ s pt1_f0_ty ``
                        ? == ( nurl_str_get pt1 0 ) 37
                        { : s sname_pt1 ( nurl_str_slice pt1 1 - ( nurl_str_len pt1 ) 1 )
                            : s var_list_pt1 ( nurl_sym_get syms ( nurl_str_cat sname_pt1 `__variants` ) )
                            ? == 0 ( nurl_str_len var_list_pt1 )
                            { = pt1_f0_ty ( nurl_sym_get syms ( nurl_str_cat3 sname_pt1 `__idx_0` `__type` ) )
                                ? & != 0 ( nurl_str_len pt1_f0_ty )
                                == ( nurl_str_get pt1_f0_ty - ( nurl_str_len pt1_f0_ty ) 1 ) 42
                                { = pt1_is_struct_handle T } {} }
                            {} }
                        {}
                        ? pt1_is_struct_handle
                        { : s h1p ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print h1p )
                            ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr1 )
                            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty pt1_f0_ty ) ) ( nurl_print `\n` )
                            ( nurl_print `  ` ) ( nurl_print cv1 )
                            ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty pt1 ) )
                            ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty pt1_f0_ty ) )
                            ( nurl_print ` ` ) ( nurl_print h1p ) ( nurl_print `, 0\n` ) }
                        { ? | == ( nurl_str_get pt1 0 ) 123
                            & == ( nurl_str_get pt1 0 ) 37
                            != ( nurl_str_get pt1 - ( nurl_str_len pt1 ) 1 ) 42
                            {  // Anon aggregate OR named non-pointer struct / enum:
                                // inttoptr + load the whole value back through the
                                // box pointer.
                                : s b1p ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print b1p )
                                ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr1 ) ( nurl_print ` to ptr\n` )
                                ( nurl_print `  ` ) ( nurl_print cv1 )
                                ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty pt1 ) )
                                ( nurl_print `, ptr ` ) ( nurl_print b1p ) ( nurl_print `\n` )
                            }
                            { ( nurl_print `  ` ) ( nurl_print cv1 )
                                ? == ( int_width pt1 ) 64
                                { ( nurl_print ` = add i64 ` ) ( nurl_print pr1 ) ( nurl_print `, 0\n` ) }
                                { ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr1 ) ( nurl_print ` to i8*\n` ) } } }
                    }
                }
                : s vp1 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print vp1 )
                ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty pt1 ) ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty pt1 ) )
                ( nurl_print ` ` ) ( nurl_print cv1 )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt1 ) )
                ( nurl_print `* ` ) ( nurl_print vp1 ) ( nurl_print `\n` )
                ( nurl_sym_def syms pv1 pt1 )
                ( nurl_sym_def syms ( nurl_str_cat pv1 `__ptr` ) vp1 )
                ? != 0 g_auto_drop_strings
                { : s a1_key ( nurl_str_cat `drop##` pt1 )
                    ? & != 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms a1_key ) )
                    == 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms ( nurl_str_cat `autodrop##` pt1 ) ) )
                    { ( mem_own_add_user_drop syms vp1 pt1 ) }
                    {}
                }
                {}
            } {}
            // Bind third payload variable (enum field 3)
            ? != 0 ( nurl_str_len pv2 ) {
                : s pt2 ( nurl_sym_get syms ( nurl_str_cat pattern_name `__payload__2` ) )
                : s pr2 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print pr2 )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty match_type ) )
                ( nurl_print ` ` ) ( nurl_print match_val ) ( nurl_print `, 3\n` )
                : s cv2 ( nurl_cg_reg cg )
                ? ( is_float_ty pt2 )
                { ( emit_enum_float_extract cv2 pt2 pr2 cg ) }
                { ? & > ( int_width pt2 ) 0 < ( int_width pt2 ) 64 {
                        ( nurl_print `  ` ) ( nurl_print cv2 )
                        ( nurl_print ` = trunc i64 ` ) ( nurl_print pr2 ) ( nurl_print ` to ` ) ( nurl_print ( nurl_llty pt2 ) ) ( nurl_print `\n` )
                    } {
                        // Mirror slot-0 reconstruction — same struct-payload hole
                        // as slot 1, one slot over (enum field 3).
                        : ~ b pt2_is_struct_handle F
                        : ~ s pt2_f0_ty ``
                        ? == ( nurl_str_get pt2 0 ) 37
                        { : s sname_pt2 ( nurl_str_slice pt2 1 - ( nurl_str_len pt2 ) 1 )
                            : s var_list_pt2 ( nurl_sym_get syms ( nurl_str_cat sname_pt2 `__variants` ) )
                            ? == 0 ( nurl_str_len var_list_pt2 )
                            { = pt2_f0_ty ( nurl_sym_get syms ( nurl_str_cat3 sname_pt2 `__idx_0` `__type` ) )
                                ? & != 0 ( nurl_str_len pt2_f0_ty )
                                == ( nurl_str_get pt2_f0_ty - ( nurl_str_len pt2_f0_ty ) 1 ) 42
                                { = pt2_is_struct_handle T } {} }
                            {} }
                        {}
                        ? pt2_is_struct_handle
                        { : s h2p ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print h2p )
                            ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr2 )
                            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty pt2_f0_ty ) ) ( nurl_print `\n` )
                            ( nurl_print `  ` ) ( nurl_print cv2 )
                            ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty pt2 ) )
                            ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty pt2_f0_ty ) )
                            ( nurl_print ` ` ) ( nurl_print h2p ) ( nurl_print `, 0\n` ) }
                        { ? | == ( nurl_str_get pt2 0 ) 123
                            & == ( nurl_str_get pt2 0 ) 37
                            != ( nurl_str_get pt2 - ( nurl_str_len pt2 ) 1 ) 42
                            {  // Anon aggregate OR named non-pointer struct / enum:
                                // inttoptr + load the whole value back through the
                                // box pointer.
                                : s b2p ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print b2p )
                                ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr2 ) ( nurl_print ` to ptr\n` )
                                ( nurl_print `  ` ) ( nurl_print cv2 )
                                ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty pt2 ) )
                                ( nurl_print `, ptr ` ) ( nurl_print b2p ) ( nurl_print `\n` )
                            }
                            { ( nurl_print `  ` ) ( nurl_print cv2 )
                                ? == ( int_width pt2 ) 64
                                { ( nurl_print ` = add i64 ` ) ( nurl_print pr2 ) ( nurl_print `, 0\n` ) }
                                { ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pr2 ) ( nurl_print ` to i8*\n` ) } } }
                    }
                }
                : s vp2 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print vp2 )
                ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty pt2 ) ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty pt2 ) )
                ( nurl_print ` ` ) ( nurl_print cv2 )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt2 ) )
                ( nurl_print `* ` ) ( nurl_print vp2 ) ( nurl_print `\n` )
                ( nurl_sym_def syms pv2 pt2 )
                ( nurl_sym_def syms ( nurl_str_cat pv2 `__ptr` ) vp2 )
                ? != 0 g_auto_drop_strings
                { : s a2_key ( nurl_str_cat `drop##` pt2 )
                    ? & != 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms a2_key ) )
                    == 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms ( nurl_str_cat `autodrop##` pt2 ) ) )
                    { ( mem_own_add_user_drop syms vp2 pt2 ) }
                    {}
                }
                {}
            } {}

            // Bind payload slots 3+ (slot 0 is handled inline above with its
            // opt/res-aware reconstruction; slots 1/2 just above). One helper
            // call per slot lifts the former 3-payload destructuring limit.
            : ~ s pb_rest pv_over
            : ~ i pb_idx 3
            ~ != 0 ( nurl_str_len pb_rest ) {
                : s pb_tok ( str_first_word pb_rest )
                = pb_rest ( str_skip_word pb_rest )
                ? ! ( seq pb_tok `_` ) { ( emit_enum_payload_bind pb_tok pb_idx pattern_name match_type match_val syms cg ) } {}
                = pb_idx + pb_idx 1
            }

            // Guard test (after payload binding so it sees the bound
            // payloads): replay the recorded guard expression, branch to
            // the body on true and to the next arm on false, then restore
            // the lexer to the body for gen_stmt below.
            ? != 0 has_guard {
                ( nurl_lex_set_pos lex guard_pos )
                : s gv ( gen_expr lex syms cg )
                : s gvt ( nurl_get_last_type )
                : ~ s gcond gv
                ? ( seq gvt `i1` ) {} {
                    : s gz ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print gz )
                    ( nurl_print ` = icmp ne ` ) ( nurl_print gvt )
                    ( nurl_print ` ` ) ( nurl_print gv ) ( nurl_print `, 0\n` )
                    = gcond gz
                }
                : s gbody ( nurl_cg_lbl cg `gbody` )
                ( nurl_print `  br i1 ` ) ( nurl_print gcond )
                ( nurl_print `, label %` ) ( nurl_print gbody )
                ( nurl_print `, label %` ) ( nurl_print next_label ) ( emit_dbg_eol )
                ( nurl_print gbody ) ( nurl_print `:\n` )
                ( nurl_sym_def syms `__cur_lbl__` gbody )
                ( nurl_lex_set_pos lex body_pos )
            } {}

            = g_did_ret 0
            // Borrow checker (Phase 0c): a `??` arm `{` is a forward
            // join. A bare (block-less) arm leaves this armed; the
            // next arm re-arms it, and the post-loop disarm clears a
            // trailing bare arm's residue.
            ( bck_set_block_kind `match-arm` )
            : i __saved_in_arm g_in_match_arm
            = g_in_match_arm 1
            // Escaping-ident snapshot, mirroring gen_cond: if this
            // arm's value is a bare load of a tracked owned i8*
            // binding, the buffer escapes through the match phi and
            // the binding's drop must be cancelled when the phi entry
            // is recorded below. Copy via nurl_str_cat — sym_get's
            // pointer dies at the arm scope's nurl_sym_pop.
            ( nurl_sym_def syms `__last_ident_name__` `` )
            : s arm_result ( gen_stmt lex syms cg )
            = g_in_match_arm __saved_in_arm
            : s arm_type ( nurl_get_last_type )
            : s arm_retid ( nurl_str_cat ( nurl_sym_get syms `__last_ident_name__` ) `` )
            : s arm_lbl ( nurl_sym_get syms `__cur_lbl__` )
            : i arm_did_ret g_did_ret
            = arms_total + arms_total 1
            ? != 0 arm_did_ret { = arms_ret + arms_ret 1 } {}

            // Phase 2D arm-local fall-through drop — only safe when the arm
            // type is void (an arm-local heap object may back a value flowing
            // through to the phi consumer; freeing here would UAF).
            ? & & != 0 g_auto_drop_strings ( seq arm_type `void` ) == arm_did_ret 0
            { ( mem_drop_new_strings syms cg old_strs_m )
                ( mem_drop_new_struct_fields syms cg old_structs_m )
                ( mem_drop_new_user_drops syms cg old_user_m ) } {}
            ? == arm_did_ret 0
            { ( mem_drop_new_closure_envs syms cg old_closure_m ) } {}
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
                    // Arm-type agreement on the LOWERED spellings, and
                    // keep the unsigned spelling when any arm carries it
                    // (an i64-literal arm beside a u64 arm) — mirrors
                    // gen_cond's `?`-join.
                    ? & != phi_count 0 ! ( seq ( nurl_llty arm_type ) ( nurl_llty phi_type ) ) { = phi_ok F } {}
                    ? ( ty_is_unsigned arm_type ) { = phi_type ( ty_to_unsigned phi_type ) } {}
                    // Ownership transfer out of the arm (see snapshot
                    // above): the value lives on through the phi.
                    ? ( seq ( nurl_llty arm_type ) `i8*` )
                    { ( mem_remove_owned_str syms
                        ( nurl_sym_get syms ( nurl_str_cat arm_retid `__ptr` ) ) ) }
                    {}
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
        : ~ s phi_full phi_entries
        ? != 0 ( nurl_str_len fallback_pred ) {
            = phi_full ( nurl_str_cat phi_entries ( nurl_str_cat `, [ undef, %` ( nurl_str_cat fallback_pred ` ]` ) ) )
        } {}
        ( nurl_print `  ` ) ( nurl_print final_reg )
        ( nurl_print ` = phi ` ) ( nurl_print ( nurl_llty phi_type ) )
        ( nurl_print ` ` ) ( nurl_print phi_full ) ( nurl_print `\n` )
        ( nurl_set_last_type phi_type )
        // Borrow propagation only matters when the match YIELDS an auto-Drop
        // enum (the value a `:`-binding might wrongly drop). For any other
        // result type — String, i, … — reset so a match on a borrowed param
        // that returns a non-enum (string_from, a count) is NOT mis-marked
        // ret_borrow.
        ( nurl_sym_def syms `__last_value_borrow__`
        ? ( __is_autodrop_enum phi_type syms ) match_scrut_borrow `` )
        // A SCALAR match result (i*/double) cannot alias the scrutinee's
        // storage, so clear `__last_ident_name__` (which still names the
        // scrutinee binding from its eval). Otherwise `^ ?? owned { _ → 0 }`
        // makes gen_ret mistake `owned` for the returned value and SKIP its
        // auto-drop — leaking it. For a non-scalar result we leave the name
        // as-is (conservative: it MIGHT be a payload view of the
        // scrutinee, and skipping the drop avoids a use-after-free).
        ? | > ( int_width phi_type ) 0 ( seq phi_type `double` )
        { ( nurl_sym_def syms `__last_ident_name__` `` ) }
        {}
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
    // Snapshot the iterated container's name (when it is a bare
    // binding) before gen_expr consumes the token, so the loop body
    // can be checked for mutation of it.
    : s fe_cont ? ( is_ident_tok ( nurl_lex_type lex ) ) ( nurl_lex_val lex ) ``
    : s slice_val ( gen_expr lex syms cg )
    : s slice_ty ( nurl_get_last_type )
    // The element's signedness rides the element TYPE (A1): a slice
    // carrier is `{ u8*, i64 }` so the sliced-out element is `u8`, and
    // the Vec carrier's `%Vec__u8` suffix demangles back to `u8` — the
    // loop binding below stores that raw type and signed-sensitive ops
    // (`/ % >> < > <= >=`) and `# i` widening read it from there.
    // Two carrier shapes feed `~ x xs { ... }`:
    //
    //   Slice  `[T`        →  slice_ty = "{ T*, i64 }"
    //                          ptr at field 0, len at field 1.
    //
    //   Vec    `( Vec T )` →  slice_ty = "%Vec__T" (= type { i8* })
    //                          field 0 is the ctl pointer; the actual
    //                          data ptr / len live in the 24-byte
    //                          control block at words 0 and 1, reached
    //                          via nurl_peek. The phantom element type
    //                          T is recovered by demangling the suffix
    //                          after `%Vec__` — round-trips through
    //                          mangle_type/demangle_type. The carrier
    //                          struct itself has no len field, so the
    //                          old "extractvalue %Vec__T %v, 1" path
    //                          produced out-of-bounds IR (clang error
    //                          "invalid indices for extractvalue"); the
    //                          Vec branch below replaces that with the
    //                          control-block accessor pair.
    : b is_vec != 0 ( nurl_str_starts slice_ty `%Vec__` )
    : ~ s ptr_ty ``
    : ~ s elem_ty ``
    : ~ s ptr_val ``
    : ~ s len_val ``
    ? is_vec {
        : i sty_len ( nurl_str_len slice_ty )
        : s suffix ( nurl_str_slice slice_ty 6 - sty_len 6 )
        = elem_ty ( demangle_type suffix )
        = ptr_ty ( nurl_str_cat elem_ty `*` )
        // ctl = extractvalue %Vec__T %v, 0
        : s ctl ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ctl )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty slice_ty ) )
        ( nurl_print ` ` ) ( nurl_print slice_val ) ( nurl_print `, 0\n` )
        // data_i64 = nurl_peek(ctl, 0); ptr = inttoptr data_i64 to T*
        : s data_int ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print data_int )
        ( nurl_print ` = call i64 @nurl_peek(i8* ` ) ( nurl_print ctl )
        ( nurl_print `, i64 0)\n` )
        = ptr_val ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ptr_val )
        ( nurl_print ` = inttoptr i64 ` ) ( nurl_print data_int )
        ( nurl_print ` to ` ) ( nurl_print ( nurl_llty ptr_ty ) ) ( nurl_print `\n` )
        // len = nurl_peek(ctl, 1)
        = len_val ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print len_val )
        ( nurl_print ` = call i64 @nurl_peek(i8* ` ) ( nurl_print ctl )
        ( nurl_print `, i64 1)\n` )
    } {
        : i slen ( nurl_str_len slice_ty )
        = ptr_ty ( nurl_str_slice slice_ty 2 - - slen 7 2 )
        = elem_ty ( nurl_str_slice ptr_ty 0 - ( nurl_str_len ptr_ty ) 1 )
        = ptr_val ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ptr_val )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty slice_ty ) )
        ( nurl_print ` ` ) ( nurl_print slice_val ) ( nurl_print `, 0\n` )
        = len_val ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print len_val )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty slice_ty ) )
        ( nurl_print ` ` ) ( nurl_print slice_val ) ( nurl_print `, 1\n` )
    }
    // Alloca for index counter
    : s idx_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print idx_ptr )
    ( nurl_print ` = alloca i64\n` )
    ( nurl_print `  store i64 0, i64* ` ) ( nurl_print idx_ptr ) ( nurl_print `\n` )
    // Alloca for the loop element variable; bind in symtable
    : s elem_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print elem_ptr )
    ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty elem_ty ) ) ( nurl_print `\n` )
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
    ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_ty ) )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty ptr_ty ) )
    ( nurl_print ` ` ) ( nurl_print ptr_val )
    ( nurl_print `, i64 ` ) ( nurl_print idx_cur ) ( nurl_print `\n` )
    : s elem_val ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print elem_val )
    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty elem_ty ) )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty ptr_ty ) )
    ( nurl_print ` ` ) ( nurl_print gep ) ( nurl_print `\n` )
    ( nurl_print `  store ` ) ( nurl_print ( nurl_llty elem_ty ) ) ( nurl_print ` ` )
    ( nurl_print elem_val ) ( nurl_print `, ` )
    ( nurl_print ( nurl_llty ptr_ty ) ) ( nurl_print ` ` ) ( nurl_print elem_ptr ) ( nurl_print `\n` )
    // Scope foreach body (see gen_cond / gen_loop).
    : ~ s old_strs_fe ``
    : ~ s old_structs_fe ``
    : ~ s old_user_fe ``
    : ~ s old_closure_fe ( nurl_sym_get syms `__owned_closure_envs__` )
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
        ( mem_drop_new_closure_envs syms cg old_closure_fe )
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
    : ~ s cv ( gen_expr lex syms cg )
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
        : ~ s old_strs_lp ``
        : ~ s old_structs_lp ``
        : ~ s old_user_lp ``
        : ~ s old_closure_lp ( nurl_sym_get syms `__owned_closure_envs__` )
        ? != 0 g_auto_drop_strings
        { = old_strs_lp ( nurl_sym_get syms `__owned_strings__` )
            = old_structs_lp ( nurl_sym_get syms `__owned_struct_fields__` )
            = old_user_lp ( nurl_sym_get syms `__user_drops__` )
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
                ( mem_drop_new_struct_fields syms cg old_structs_lp )
                ( mem_drop_new_user_drops syms cg old_user_lp ) } {}
            ( mem_drop_new_closure_envs syms cg old_closure_lp )
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
    : ~ s last `undef`
    : ~ b any F
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        = last ( gen_stmt lex syms cg )
        = any T
    }
    ( nurl_lex_advance lex )
    ( bck_block_exit )
    // An empty block `{}` is the unit / void value. Without typing it as
    // void, `nurl_get_last_type` retains whatever it was before the block
    // (i64 by default, i1 inside a conditional), so a `^ {}` in a void
    // function emitted `ret i64 undef` — invalid IR. Typing it void also
    // makes a value-position `? c { v } {}` (empty else) consistently
    // void rather than a dead `phi [v, undef]`, which in turn lets the
    // owned-string auto-drop fire correctly at the arm boundary.
    // (A non-empty block's type is set by its trailing statement.)
    ? ! any { ( nurl_set_last_type `void` ) } {}
    last
}

@ __dangling_operand_msg → s {
    ^ `literal as a statement has no effect — its value is discarded. This usually means a prefix operator was given one operand too many (a dangling operand): e.g. '& x 255 0x40' parses as '& x 255' and silently drops the 0x40. Check the operator's arity.`
}

// The literal diagnostic's general sibling (critic A2): a bare
// identifier / operator expression / cast / field read in statement
// position whose value is discarded. WARN rather than die — unlike a
// bare literal these shapes name real bindings, and the residual
// prefix-arity cascade they catch (an operator short an argument
// swallowed the next statement's leading token, leaving this dead
// remainder) is otherwise completely silent. `line` is the dead
// statement's own line — lex has already advanced to the next
// statement when the block iterator fires this.
@ __dead_value_msg i line → s {
    ^ ( nurl_str_cat3 `the statement on line ` ( nurl_str_int line )
    ` has no effect — it produces a value that is discarded. If it was meant as an operand, the prefix operator before it is short an argument (fixed arity, no closing bracket); otherwise bind the value (': T name …') or remove the statement.` )
}

@ gen_block_stmts i lex i syms i cg → v {
    : i bck_line ( nurl_lex_line lex )
    ( expect lex TT_LBRACE )
    ( bck_block_enter bck_line )
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        ( gen_stmt lex syms cg )
        // Every statement in a void block has its value discarded, so a
        // bare literal here is dead — reject it (dangling operand).
        ? != 0 g_stmt_bare_lit { ( die lex ( __dangling_operand_msg ) ) } {}
        ? != 0 g_stmt_bare_value { ( warn lex ( __dead_value_msg g_stmt_bare_value ) ) } {}
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
    : ~ s last `undef`
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        = last ( gen_stmt lex syms cg )
        // A bare literal that is NOT the block's final expression (its
        // return value) has its value discarded — reject it as a dangling
        // operand. The final literal (next token `}`) is the legitimate
        // block result and is left alone. Same tail exemption for the
        // dead-value warning below.
        ? & != 0 g_stmt_bare_lit != ( nurl_lex_type lex ) TT_RBRACE
        { ( die lex ( __dangling_operand_msg ) ) } {}
        ? & != 0 g_stmt_bare_value != ( nurl_lex_type lex ) TT_RBRACE
        { ( warn lex ( __dead_value_msg g_stmt_bare_value ) ) } {}
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
    { : ~ s rest ( nurl_sym_get syms `__owned_slices__` )
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
                ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty ty ) )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty ty ) )
                ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                : s dp ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print dp )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty ty ) )
                ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `, 0\n` )
                : s raw ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print raw )
                ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty tptr ) )
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

// Panic-unwind journal: record an owned i8* (loaded from its alloca
// `slot`) so a panic that longjmps over the scope-exit nurl_free still
// reclaims it (docs/MEMORY.md §7). nurl_free removes it again on the
// normal path, so this never causes a double-free. The runtime push is
// a no-op outside a recover extent, so the cost is one branch.
@ mem_journal_push_str i cg s slot → v {
    : s p ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print p )
    ( nurl_print ` = load i8*, i8** ` ) ( nurl_print slot ) ( nurl_print `\n` )
    ( nurl_print `  call void @nurl_journal_push(i8* ` ) ( nurl_print p ) ( nurl_print `)\n` )
}

// Panic-unwind journal for an owned slice. The alloca `slot` holds a
// `{ T*, i64 }` value; record its buffer pointer (field 0) so a panic
// reclaims it. Like a string a slice is captured by value (its type is
// `{ ... }`, not `%Name`), so it cannot escape a recover extent by
// reference and needs no forget hook.
@ mem_journal_push_slice i cg s ty s slot → v {
    : i tylen ( nurl_str_len ty )
    : s tptr ( nurl_str_slice ty 2 - tylen 9 )
    : s sv ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print sv )
    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty ty ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty ty ) )
    ( nurl_print `* ` ) ( nurl_print slot ) ( nurl_print `\n` )
    : s dp ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print dp )
    ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty ty ) )
    ( nurl_print ` ` ) ( nurl_print sv ) ( nurl_print `, 0\n` )
    : s raw ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print raw )
    ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty tptr ) )
    ( nurl_print ` ` ) ( nurl_print dp ) ( nurl_print ` to i8*\n` )
    ( nurl_print `  call void @nurl_journal_push(i8* ` ) ( nurl_print raw ) ( nurl_print `)\n` )
}

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
    { : ~ s rest ( nurl_sym_get syms `__owned_strings__` )
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
    : ~ s out `, `
    : ~ i i 0
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
    : ~ s entry ( nurl_str_cat3 ptr ` ` sname )
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
        : ~ s rest idxs
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
    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty agg_ty ) )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty agg_ty ) )
    ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
    ? ( seq kind `str` )
    { : s fv ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print fv )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty agg_ty ) )
        ( nurl_print ` ` ) ( nurl_print sv ) ( nurl_print idx_list )
        ( nurl_print `\n` )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print fv ) ( nurl_print `)` ) ( emit_dbg_eol )
    }
    { : s slice_ty ( nurl_sym_get syms ( nurl_str_cat3 leaf_sname `__idx_` ( nurl_str_cat leaf_idx `__type` ) ) )
        : i slen ( nurl_str_len slice_ty )
        : s tptr ( nurl_str_slice slice_ty 2 - slen 9 )
        : s sv2 ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print sv2 )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty agg_ty ) )
        ( nurl_print ` ` ) ( nurl_print sv ) ( nurl_print idx_list )
        ( nurl_print `\n` )
        : s dp ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print dp )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty slice_ty ) )
        ( nurl_print ` ` ) ( nurl_print sv2 ) ( nurl_print `, 0\n` )
        : s raw ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print raw )
        ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty tptr ) )
        ( nurl_print ` ` ) ( nurl_print dp ) ( nurl_print ` to i8*\n` )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print raw ) ( nurl_print `)` ) ( emit_dbg_eol )
    }
}

// Panic-unwind journal for an owned struct-field leaf. Mirrors
// mem_emit_struct_field_drop's load + extractvalue chain, but records
// the leaf pointer for recover-unwind cleanup instead of freeing it
// (docs/MEMORY.md §7). nurl_free removes it again on the normal path.
@ mem_journal_push_struct_field i syms i cg s ptr s sname s path s kind s leaf_sname s leaf_idx → v {
    : s agg_ty ( nurl_str_cat `%` sname )
    : s idx_list ( mem_path_to_indices path )
    : s sv ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print sv )
    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty agg_ty ) )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty agg_ty ) )
    ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
    ? ( seq kind `str` )
    { : s fv ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print fv )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty agg_ty ) )
        ( nurl_print ` ` ) ( nurl_print sv ) ( nurl_print idx_list )
        ( nurl_print `\n` )
        ( nurl_print `  call void @nurl_journal_push(i8* ` ) ( nurl_print fv ) ( nurl_print `)\n` )
    }
    { : s slice_ty ( nurl_sym_get syms ( nurl_str_cat3 leaf_sname `__idx_` ( nurl_str_cat leaf_idx `__type` ) ) )
        : i slen ( nurl_str_len slice_ty )
        : s tptr ( nurl_str_slice slice_ty 2 - slen 9 )
        : s sv2 ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print sv2 )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty agg_ty ) )
        ( nurl_print ` ` ) ( nurl_print sv ) ( nurl_print idx_list )
        ( nurl_print `\n` )
        : s dp ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print dp )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty slice_ty ) )
        ( nurl_print ` ` ) ( nurl_print sv2 ) ( nurl_print `, 0\n` )
        : s raw ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print raw )
        ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty tptr ) )
        ( nurl_print ` ` ) ( nurl_print dp ) ( nurl_print ` to i8*\n` )
        ( nurl_print `  call void @nurl_journal_push(i8* ` ) ( nurl_print raw ) ( nurl_print `)\n` )
    }
}

// Emit a journal push for every owned struct-field entry tied to alloca
// `ptr` (the binding just registered by mem_register_agg_owned_fields).
@ mem_journal_push_agg_fields i syms i cg s ptr → v {
    : ~ s rest ( nurl_sym_get syms `__owned_struct_fields__` )
    ~ != 0 ( nurl_str_len rest ) {
        : s eptr ( str_first_word rest ) = rest ( str_skip_word rest )
        : s sname ( str_first_word rest ) = rest ( str_skip_word rest )
        : s path ( str_first_word rest ) = rest ( str_skip_word rest )
        : s kind ( str_first_word rest ) = rest ( str_skip_word rest )
        : s leaf_sname ( str_first_word rest ) = rest ( str_skip_word rest )
        : s leaf_idx ( str_first_word rest ) = rest ( str_skip_word rest )
        ? ( seq eptr ptr )
        { ( mem_journal_push_struct_field syms cg eptr sname path kind leaf_sname leaf_idx ) }
        {}
    }
}

// Panic-unwind journal: forget the heap leaves of struct value `sval`
// (type `vt` = "%Name") that is ESCAPING the current recover extent —
// e.g. assigned into a by-ref-captured caller binding. Walks the struct
// type's fields and, for every owned heap field (i8* / slice / nested
// named struct), removes its pointer from the journal so a later panic's
// drain does not free what the caller now owns (docs/MEMORY.md §7).
// Over-approximates: forgetting a field that was never journaled is a
// harmless no-op, so it is always safe to call.
@ mem_journal_forget_struct i syms i cg s sval s vt → v {
    ? != ( nurl_str_get vt 0 ) 37 { ^ v } {}
    : s sname ( nurl_str_slice vt 1 - ( nurl_str_len vt ) 1 )
    : s fc ( nurl_sym_get syms ( nurl_str_cat sname `__field_count` ) )
    ? == 0 ( nurl_str_len fc ) { ^ v } {}
    : i n ( nurl_str_to_int fc )
    : ~ i i 0
    ~ < i n {
        : s ft ( nurl_sym_get syms
        ( nurl_str_cat3 sname `__idx_` ( nurl_str_cat ( nurl_str_int i ) `__type` ) ) )
        ? ( seq ( nurl_llty ft ) `i8*` )
        { : s fv ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print fv )
            ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty vt ) )
            ( nurl_print ` ` ) ( nurl_print sval ) ( nurl_print `, ` )
            ( nurl_print ( nurl_str_int i ) ) ( nurl_print `\n` )
            ( nurl_print `  call void @nurl_journal_forget(i8* ` ) ( nurl_print fv ) ( nurl_print `)\n` )
        }
        { ? ( mem_is_slice_ty ft )
            { : i flen ( nurl_str_len ft )
                : s tptr ( nurl_str_slice ft 2 - flen 9 )
                : s sv2 ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print sv2 )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty vt ) )
                ( nurl_print ` ` ) ( nurl_print sval ) ( nurl_print `, ` )
                ( nurl_print ( nurl_str_int i ) ) ( nurl_print `\n` )
                : s dp ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print dp )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ft )
                ( nurl_print ` ` ) ( nurl_print sv2 ) ( nurl_print `, 0\n` )
                : s raw ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print raw )
                ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty tptr ) )
                ( nurl_print ` ` ) ( nurl_print dp ) ( nurl_print ` to i8*\n` )
                ( nurl_print `  call void @nurl_journal_forget(i8* ` ) ( nurl_print raw ) ( nurl_print `)\n` )
            }
            { ? & == ( nurl_str_get ft 0 ) 37 != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat ( nurl_str_slice ft 1 - ( nurl_str_len ft ) 1 ) `__field_count` ) ) )
                { : s iv ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print iv )
                    ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty vt ) )
                    ( nurl_print ` ` ) ( nurl_print sval ) ( nurl_print `, ` )
                    ( nurl_print ( nurl_str_int i ) ) ( nurl_print `\n` )
                    ( mem_journal_forget_struct syms cg iv ft ) }
                {} }
        }
        = i + i 1
    }
}

@ mem_drop_owned_struct_fields i syms i cg s skip_ptr → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : ~ s rest ( nurl_sym_get syms `__owned_struct_fields__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s ptr ( str_first_word rest ) = rest ( str_skip_word rest )
            : s sname ( str_first_word rest ) = rest ( str_skip_word rest )
            : s path ( str_first_word rest ) = rest ( str_skip_word rest )
            : s kind ( str_first_word rest ) = rest ( str_skip_word rest )
            : s leaf_sname ( str_first_word rest ) = rest ( str_skip_word rest )
            : s leaf_idx ( str_first_word rest ) = rest ( str_skip_word rest )
            // skip_ptr names a struct binding whose owned fields ESCAPE
            // as the return value (A4c ownership transfer) — the caller
            // re-registers them, so dropping them here would dangle the
            // returned copy's field pointers (use-after-free).
            ? & != 0 ( nurl_str_len skip_ptr ) ( seq ptr skip_ptr )
            {}
            { ( mem_emit_struct_field_drop syms cg ptr sname path kind leaf_sname leaf_idx ) }
        }
    }
    {}
}

// A4c (caller side): a `: T x ( f )` binding whose RHS is a call to a
// struct-returning function carries its owned fields in
// `__last_call_ret_struct_fields__` (set by gen_call), but
// `mem_register_agg_owned_fields` reads `__last_agg_owned_fields__` —
// only a direct `@ T {…}` RHS populates that. Bridge the two: when the
// agg list is empty but the call list isn't, copy it over so the
// caller re-registers exactly the fields the callee transferred out.
@ __propagate_call_struct_fields i syms → v {
    : s agg ( nurl_sym_get syms `__last_agg_owned_fields__` )
    ? & != 0 g_auto_drop_strings == 0 ( nurl_str_len agg )
    { : s call ( nurl_sym_get syms `__last_call_ret_struct_fields__` )
        ? != 0 ( nurl_str_len call )
        { ( nurl_sym_def syms `__last_agg_owned_fields__` call ) }
        {}
    }
    {}
}

// A4c: compute the owned-struct-field ownership transfer for a return.
// A function returning a by-value struct with fresh-owned fields
// transfers those allocations to the caller; the callee must NOT drop
// them (it never bound the escaping copy) and the caller must register
// them. Two return shapes:
//   * `^ v` / implicit `v` — a struct BINDING whose fields are in
//     `__owned_struct_fields__`. Its drop is skipped (returned ptr),
//     and its field list is reformatted for the caller.
//   * `^ @ T { … }` / `^ ( mk )` — a direct construction / a call that
//     already returns owned fields. No binding to skip;
//     `__last_agg_owned_fields__` (set by gen_agg_lit) or the callee's
//     propagated `__last_call_ret_struct_fields__` carries the list.
// Sets `__fn_ret_struct_owned__` to the colon-format field list the
// caller re-registers, and returns the binding ptr to skip-drop (empty
// for the non-binding shapes). NOT fired for single-pointer-handle
// structs (Vec/String) — those ride the slot and use the string / user-
// drop paths; only multi-field structs with owned leaf fields qualify,
// which structurally excludes stdlib's incremental-build-then-`^ binding`
// returns (they never register agg owned fields on the returned struct).
@ mem_ret_struct_transfer i syms s lt s ret_ident → s {
    ? == 0 g_auto_drop_strings { ^ `` } {}
    // Only a named non-pointer struct return can carry owned fields.
    ? | == 0 ( nurl_str_len lt ) != ( nurl_str_get lt 0 ) 37 { ^ `` } {}
    ? == ( nurl_str_get lt - ( nurl_str_len lt ) 1 ) 42 { ^ `` } {}
    : s rid_ptr ( nurl_sym_get syms ( nurl_str_cat ret_ident `__ptr` ) )
    : s from_binding ( mem_collect_struct_fields_for syms rid_ptr )
    ? != 0 ( nurl_str_len from_binding )
    { ( nurl_sym_def syms `__fn_ret_struct_owned__` from_binding )
        ^ rid_ptr }
    {}
    // Non-binding shapes: a direct `@ T {…}` (gen_agg_lit set
    // `__last_agg_owned_fields__`) or a call returning owned fields
    // (gen_call set `__last_call_ret_struct_fields__`).
    : s from_agg ( nurl_sym_get syms `__last_agg_owned_fields__` )
    ? != 0 ( nurl_str_len from_agg )
    { ( nurl_sym_def syms `__fn_ret_struct_owned__` from_agg )
        ^ `` }
    {}
    : s from_call ( nurl_sym_get syms `__last_call_ret_struct_fields__` )
    ? != 0 ( nurl_str_len from_call )
    { ( nurl_sym_def syms `__fn_ret_struct_owned__` from_call ) }
    {}
    ^ ``
}

// Collect a returned struct binding's owned fields, reformatted from the
// `__owned_struct_fields__` 6-token groups (`<ptr> <sname> <path> <kind>
// <leaf_sname> <leaf_idx>`) into the agg-owned propagation format
// (`<path>:<kind>:<leaf_sname>:<leaf_idx>`), keeping only entries whose
// ptr matches `want_ptr`. Empty when the binding owns no fields. Used by
// gen_ret to hand the caller exactly the field set to re-register (A4c).
@ mem_collect_struct_fields_for i syms s want_ptr → s {
    ? == 0 ( nurl_str_len want_ptr ) { ^ `` } {}
    : ~ s out ``
    : ~ s rest ( nurl_sym_get syms `__owned_struct_fields__` )
    ~ != 0 ( nurl_str_len rest ) {
        : s ptr ( str_first_word rest ) = rest ( str_skip_word rest )
        : s sname ( str_first_word rest ) = rest ( str_skip_word rest )
        : s path ( str_first_word rest ) = rest ( str_skip_word rest )
        : s kind ( str_first_word rest ) = rest ( str_skip_word rest )
        : s leaf_sname ( str_first_word rest ) = rest ( str_skip_word rest )
        : s leaf_idx ( str_first_word rest ) = rest ( str_skip_word rest )
        ? ( seq ptr want_ptr )
        { : s tok ( nurl_str_cat4 path `:` kind ( nurl_str_cat4 `:` leaf_sname `:` leaf_idx ) )
            = out ? == 0 ( nurl_str_len out ) tok ( nurl_str_cat3 out ` ` tok )
        }
        {}
    }
    ^ out
}

// ── Phase 2D: arm-local delta drop ────────────────────────────────
// When an arm falls through (no `^ ret`) and its `nurl_sym_pop` is about
// to discard the arm scope, we must free owned bindings added DURING the
// arm or they leak. `mem_own_add_str` / `mem_own_add_struct_field` store
// the concatenation of the parent's list plus arm-local entries in the
// pushed scope's `__owned_strings__` / `__owned_struct_fields__`. To drop
// only the arm-local delta, snapshot the parent's list string before
// `nurl_sym_push`, then at fall-through drop every entry whose alloca
// pointer is NOT word-contained in that snapshot. Membership (not
// prefix-length) is the protocol because `mem_remove_owned_str` —
// ownership transfer on `= outer x` — may delete a word from the
// MIDDLE of the current list mid-arm; alloca register names are unique
// per function, so word membership is exact.

@ mem_drop_new_strings i syms i cg s old_list → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : ~ s rest ( nurl_sym_get syms `__owned_strings__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s ptr ( str_first_word rest )
            = rest ( str_skip_word rest )
            ? ( str_contains_word old_list ptr )
            {}
            { : s v ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print v )
                ( nurl_print ` = load i8*, i8** ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print v ) ( nurl_print `)` ) ( emit_dbg_eol )
            }
        }
    }
    {}
}

@ mem_drop_new_struct_fields i syms i cg s old_list → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : ~ s rest ( nurl_sym_get syms `__owned_struct_fields__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s ptr ( str_first_word rest ) = rest ( str_skip_word rest )
            : s sname ( str_first_word rest ) = rest ( str_skip_word rest )
            : s path ( str_first_word rest ) = rest ( str_skip_word rest )
            : s kind ( str_first_word rest ) = rest ( str_skip_word rest )
            : s leaf_sname ( str_first_word rest ) = rest ( str_skip_word rest )
            : s leaf_idx ( str_first_word rest ) = rest ( str_skip_word rest )
            // A binding's several owned fields share one alloca ptr and
            // are registered together, so ptr-membership decides for
            // the whole group consistently.
            ? ( str_contains_word old_list ptr )
            {}
            { ( mem_emit_struct_field_drop syms cg ptr sname path kind leaf_sname leaf_idx ) }
        }
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

// Emit a `void(i8*)` journal-drop thunk for an owned value of LLVM type
// `llvm` whose typed destructor is `drop__<mangle>`: load the value from
// its alloca and run the destructor. Used on the panic-unwind path to
// replay a typed drop the longjmp skips. Deduped + recorded under
// `jdrop##<mangle>` so the push site can gate on the thunk existing.
// Called for both user `% Drop` impls and autodrop enums (both register
// `drop##` and emit `drop__<mangle>`).
@ emit_jdrop_thunk s llvm s mangle → v {
    : s donekey ( nurl_str_cat `jdrop##` mangle )
    ? != 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms donekey ) ) { ^ v } {}
    ( nurl_sym_def g_impl_name_syms donekey `1` )
    ( nurl_print `define void @__jdrop_` ) ( nurl_print mangle )
    ( nurl_print `(i8* %p) {\nentry:\n` )
    ( nurl_print `  %t = bitcast i8* %p to ` ) ( nurl_print llvm ) ( nurl_print `*\n` )
    ( nurl_print `  %v = load ` ) ( nurl_print llvm ) ( nurl_print `, ` ) ( nurl_print llvm ) ( nurl_print `* %t\n` )
    ( nurl_print `  call void @drop__` ) ( nurl_print mangle )
    ( nurl_print `(` ) ( nurl_print llvm ) ( nurl_print ` %v)\n  ret void\n}\n` )
}

// ── Closure-env reclamation for `:`-bound capturing closures (§7.4) ──
// A `: f \ → … x …` binding whose closure captures owns a heap env block
// that auto-drop never saw allocated. `__owned_closure_envs__` lists such
// binding names; the env is freed at function exit UNLESS the binding
// ESCAPES (returned, stored, passed to a non-borrow / decomposing callee,
// or captured into another closure) — every escape site removes the name,
// so the drain only frees an env whose closure provably cannot outlive
// the frame. Removal is monotonic (escape sites only), so an
// escape-then-borrow ordering can never re-arm a freed env.
@ mem_own_closure_add i syms s name → v {
    : s cur ( nurl_sym_get syms `__owned_closure_envs__` )
    ? ( str_contains_word cur name ) {}
    { ( nurl_sym_def syms `__owned_closure_envs__`
        ? == 0 ( nurl_str_len cur ) name ( nurl_str_cat3 cur ` ` name ) ) }
}

// Escape: drop `name` from the owned-closure set so its env is NOT freed
// at function exit (its closure outlives the frame; the consumer owns the
// env now). A no-op if `name` was never a tracked closure binding.
@ mem_own_closure_remove i syms s name → v {
    : s cur ( nurl_sym_get syms `__owned_closure_envs__` )
    ? & != 0 ( nurl_str_len name ) ( str_contains_word cur name )
    { : ~ s out ``
        : ~ s rest cur
        ~ != 0 ( nurl_str_len rest ) {
            : s w ( str_first_word rest ) = rest ( str_skip_word rest )
            ? ( seq w name ) {}
            { = out ? == 0 ( nurl_str_len out ) w ( nurl_str_cat3 out ` ` w ) }
        }
        ( nurl_sym_def syms `__owned_closure_envs__` out ) }
    {}
}

// Drain: free the env of every still-owned closure binding. Emitted at
// each function-exit drop point (gen_ret + the epilogue), mirroring
// mem_drop_owned_strings. Loads the closure value, extracts field 1 (the
// env i8*), and frees it (NULL-safe). Guarded on no active defers, like
// the sibling drop emitters.
// Emit the env free for one closure binding `name`: load the closure
// value, extract field 1 (the env i8*), free it. NULL-safe.
@ mem_emit_closure_env_drop i syms i cg s name → v {
    : s ty ( nurl_sym_get syms name )
    : s ptr ( nurl_sym_get syms ( nurl_str_cat name `__ptr` ) )
    ? & & != 0 ( nurl_str_len ty ) != 0 ( nurl_str_len ptr )
    == ( nurl_str_get ty 0 ) 123
    { : s cv ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print cv ) ( nurl_print ` = load ` )
        ( nurl_print ( nurl_llty ty ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty ty ) ) ( nurl_print `* ` )
        ( nurl_print ptr ) ( nurl_print `\n` )
        : s ev ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ev ) ( nurl_print ` = extractvalue ` )
        ( nurl_print ( nurl_llty ty ) ) ( nurl_print ` ` ) ( nurl_print cv ) ( nurl_print `, 1\n` )
        ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print ev ) ( nurl_print `)` )
        ( emit_dbg_eol )
    }
    {}
}

@ mem_drop_closure_envs i syms i cg → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : ~ s rest ( nurl_sym_get syms `__owned_closure_envs__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s name ( str_first_word rest ) = rest ( str_skip_word rest )
            ( mem_emit_closure_env_drop syms cg name )
        }
    }
    {}
}

// Block-delta drain (docs/MEMORY.md §7.4): free the env of every closure
// binding registered SINCE `old_list` (i.e. inside the just-finished
// block / loop body), and shrink the owned set back to those that
// predate the block. Frees a loop-local closure each iteration so a
// named closure created in a loop does not leak unboundedly. Mirrors
// mem_drop_new_user_drops.
@ mem_drop_new_closure_envs i syms i cg s old_list → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : ~ s rest ( nurl_sym_get syms `__owned_closure_envs__` )
        : ~ s keep ``
        ~ != 0 ( nurl_str_len rest ) {
            : s name ( str_first_word rest ) = rest ( str_skip_word rest )
            ? ( str_contains_word old_list name )
            { = keep ? == 0 ( nurl_str_len keep ) name ( nurl_str_cat3 keep ` ` name ) }
            { ( mem_emit_closure_env_drop syms cg name ) }
        }
        ( nurl_sym_def syms `__owned_closure_envs__` keep )
    }
    {}
}

// Panic-unwind journal for a user `% Drop` value. `ptr` is its alloca
// (`<vt>*`); record it with the type's `__jdrop_<mangle>` thunk so a
// panic replays the typed destructor (docs/MEMORY.md §7). Unlike the raw
// kinds, the entry is keyed by the alloca (not a heap pointer), so the
// compiler must forget it explicitly at every normal drop site
// (mem_drop_user_drops / mem_drop_new_user_drops) — done there.
@ mem_journal_push_userdrop i syms i cg s ptr s vt → v {
    : s impl_mangle ( nurl_sym_get g_impl_name_syms ( nurl_str_cat `drop##` vt ) )
    ? == 0 ( nurl_str_len impl_mangle ) { ^ v } {}
    // Only journal when the `__jdrop_<mangle>` thunk has been emitted
    // (gate against a forward-defined impl whose thunk isn't out yet —
    // skipping just means that value isn't reclaimed on panic, never a
    // dangling reference to a missing thunk).
    ? == 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms ( nurl_str_cat `jdrop##` impl_mangle ) ) ) { ^ v } {}
    : s bc ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print bc )
    ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print `* ` ) ( nurl_print ptr )
    ( nurl_print ` to i8*\n` )
    ( nurl_print `  call void @nurl_journal_push_drop(i8* ` ) ( nurl_print bc )
    ( nurl_print `, ptr @__jdrop_` ) ( nurl_print impl_mangle ) ( nurl_print `)\n` )
}

// Forget a user `% Drop` value's journal entry (keyed by its alloca) —
// emitted wherever its typed drop is run on the normal path, so a later
// panic in the same extent cannot replay an already-run destructor.
@ mem_journal_forget_userdrop i cg s ptr s vt → v {
    : s bc ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print bc )
    ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print `* ` ) ( nurl_print ptr )
    ( nurl_print ` to i8*\n` )
    ( nurl_print `  call void @nurl_journal_forget(i8* ` ) ( nurl_print bc ) ( nurl_print `)\n` )
}

@ mem_drop_user_drops i syms i cg s skip_ptr → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : ~ s rest ( nurl_sym_get syms `__user_drops__` )
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
                    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty vt ) )
                    ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                    ( nurl_print `  call void @` ) ( nurl_print impl_name )
                    ( nurl_print `(` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `)` ) ( emit_dbg_eol )
                }
                {}
            }
            // Forget the journal entry regardless of branch: this scope's
            // alloca dies at exit, so a later panic must not drain it.
            // (Whether the value was dropped here or escaped up, its
            // alloca-keyed entry is now stale.)
            ( mem_journal_forget_userdrop cg ptr vt )
        }
    }
    {}
}

@ mem_drop_new_user_drops i syms i cg s old_list → v {
    : s dtop ( nurl_sym_get syms `__defer_top__` )
    ? == 0 ( nurl_str_len dtop )
    { : ~ s rest ( nurl_sym_get syms `__user_drops__` )
        ~ != 0 ( nurl_str_len rest ) {
            : s ptr ( str_first_word rest ) = rest ( str_skip_word rest )
            : s vt ( str_first_word rest ) = rest ( str_skip_word rest )
            : s impl_key ( nurl_str_cat `drop##` vt )
            : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
            ? | ( str_contains_word old_list ptr )
            == 0 ( nurl_str_len impl_mangle_key )
            {}
            { : s impl_name ( nurl_str_cat `drop__` impl_mangle_key )
                : s v ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print v )
                ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty vt ) )
                ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                ( nurl_print `  call void @` ) ( nurl_print impl_name )
                ( nurl_print `(` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print ` ` ) ( nurl_print v ) ( nurl_print `)` ) ( emit_dbg_eol )
                // Forget the now-dropped value's journal entry so a later
                // panic in this function cannot replay its destructor.
                ( mem_journal_forget_userdrop cg ptr vt )
            }
        }
    }
    {}
}

// ── Ownership transfer on assignment ──────────────────────────────
// `= outer x` where x is an owned i8* binding COPIES the pointer: the
// heap buffer now lives on through `outer`, so x's scheduled drop must
// be cancelled or the arm/loop/fn-exit free turns `outer` into a
// dangling pointer (observed as corrupted IR when the compiler's own
// `: s r ( nurl_cg_reg cg )` arm-locals escaped into outer mutables).
// Conservative direction: remove x's entry — worst case the buffer
// leaks (when `outer` itself is untracked), never a use-after-free.
// Removal filters x's alloca-ptr word out of the CURRENT scope's
// `__owned_strings__`; the membership-based delta protocol above stays
// consistent under mid-list deletion.
@ mem_remove_owned_str i syms s ptr → v {
    : s cur ( nurl_sym_get syms `__owned_strings__` )
    ? & != 0 ( nurl_str_len ptr ) ( str_contains_word cur ptr )
    { : ~ s out ``
        : ~ s rest cur
        ~ != 0 ( nurl_str_len rest ) {
            : s w ( str_first_word rest )
            = rest ( str_skip_word rest )
            ? ( seq w ptr )
            {}
            { = out ? == 0 ( nurl_str_len out ) w ( nurl_str_cat3 out ` ` w ) }
        }
        ( nurl_sym_def syms `__owned_strings__` out )
    }
    {}
}

// ── Borrow checker — analysis substrate ─────────────────────────────
//
// The borrow checker is a diagnostic-only pass: it inspects the
// program and may emit `error:` / `warning:`, but it NEVER emits IR.
// A borrow-clean program therefore compiles to byte-identical IR
// whether --borrowck is on or off, and the bootstrap fixed point is
// unaffected. Every entry point below is a no-op when g_borrowck is 0.
//
// The substrate hosts the borrow rules (move checking, alias /
// double-free, escape analysis, iterator invalidation). Each rule
// is independently gated, so an individual class hangs its
// rules off the per-function CFG + ownership lattice built here.

// ── Per-function statement-list capture ────────────────────────────
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
//   1. A bare-identifier argument passed to a `*_free` destructor
//      (the typed NURL heap destructors `vec_free`, `string_free`,
//      …) — but NOT raw `nurl_free`, which frees `*T` / i8* FFI
//      memory the borrow checker does not track. gen_call detects it.
//
//   2. A binding-to-binding copy `: T b a` of an owned heap value.
//      `b` becomes the value's owner; `a` is moved. This makes the
//      silent-alias double-free (`: T b a` then both freed)
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

// ── Borrow checker — iterator invalidation ─────────────────────────
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
// A binding present on only one side still joins against BCK_UNINIT on
// the other — and crucially that join goes through `bck_join`, which
// maps UNINIT⊔MOVED to MaybeMoved (NOT Moved): a binding moved on only
// the `b` path must not surface as *definitely* moved at the merge.
// (Copying the `b`-only token verbatim — the old shortcut — violated
// that: a foreach element or loop-local freed in the body came back
// from the loop's fixpoint join as Moved and was wrongly flagged as a
// use-after-move on re-read.) `out` starts fresh and every `= out ...`
// builds a fresh string — aliasing a loop-local would double-free at
// auto-drop.
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
        : s nm ( bck_tok_name tok )
        ? == BCK_UNINIT ( bck_st_get a nm ) {
            : i vj ( bck_join BCK_UNINIT ( bck_tok_val tok ) )
            : s nt ( nurl_str_cat3 nm `=` ( nurl_str_int vj ) )
            = out ? == 0 ( nurl_str_len out )
            ( nurl_str_cat nt `` )
            ( nurl_str_cat3 out ` ` nt )
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

// Render one borrow-checker error in the front-end's diagnostic shape:
//   file:line: error: <msg>
//       <source line text>
// Borrow checks fire after parsing has moved past the offending token,
// so only file+line are known: the source line is re-read from disk and
// echoed, but no caret is drawn — a guessed column would lie. Shared by
// every borrow-checker emitter so the format can't drift from `die`'s.
@ bck_emit_error s file i line s msg → v {
    ( nurl_eprintln ( nurl_str_cat ( nurl_str_cat3 file `:` ( nurl_str_int line ) )
    ( nurl_str_cat `: error: ` msg ) ) )
    // Owned strings (`src`, `lt`) are reclaimed by auto-drop at scope
    // exit — no manual frees here (they would double-free).
    : s src ( nurl_read_file file )
    ? != 0 ( nurl_str_len src ) {
        : s lt ( __src_line_text src ( nurl_str_len src ) line )
        ? != 0 ( nurl_str_len lt ) { ( nurl_eprintln lt ) } {}
    } {}
    = g_bck_errors + g_bck_errors 1
}

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
        ( bck_emit_error ( nurl_sym_get g_bck `file` ) useline
        ( nurl_str_cat4 `use of moved value '` name
        `' — it was consumed at line ` ( nurl_str_cat3 ml
        ` (pass a fresh value or rebind it before reuse)` `` ) ) )
    }
}

// Flag any read of a definitely-Moved binding as a use-after-move.
// MaybeMoved (a conditional move at a CFG join) is deliberately NOT
// flagged — erroring only on a definite move keeps this check
// false-positive-free.
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
                // Pass the controlling `~ cond` reads (carried in the
                // block row's reads field) and its line so bck_loop can
                // re-check them against the loop's back-edge state.
                = st ( bck_loop + p 1 eb st ( bck_field rec 2 )
                ( nurl_str_to_int ( bck_field rec 3 ) ) )
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

// Build the loop's back-edge seed: the state on entry to iterations
// >= 2. Every binding that already existed BEFORE the loop (`pre`)
// keeps its pre value, EXCEPT one the body leaves Moved at exit
// (`post`) — that one is carried in as Moved, because the previous
// iteration consumed it. Bindings absent from `pre` (declared inside
// the loop, or a foreach element) are fresh every iteration and are
// deliberately dropped, so they never carry a stale Moved state.
@ bck_loop_carry_seed s pre s post → s {
    : ~ s out ( nurl_str_cat `` `` )
    : ~ s rest pre
    ~ != 0 ( nurl_str_len rest ) {
        : s tok ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s nm ( bck_tok_name tok )
        : i carried ? == BCK_MOVED ( bck_st_get post nm )
        BCK_MOVED ( bck_tok_val tok )
        : s nt ( nurl_str_cat3 nm `=` ( nurl_str_int carried ) )
        = out ? == 0 ( nurl_str_len out ) nt ( nurl_str_cat3 out ` ` nt )
    }
    out
}

// `~` loop — the body carries a back-edge, so re-enter it until the
// state at the loop head stops changing (the join of the head state
// with the body's exit state). The 16-iteration cap is a safety
// bound; the height-7 lattice converges in far fewer.
//
// After the fixpoint, a second pass catches the loop-carried
// use-after-move (the classic "free inside a loop" double-free): an
// outer binding the body moves and never re-binds is Moved on entry
// to the next iteration, so re-reading it — in the body, or in the
// `~ cond` re-check (`cond_reads` / `cond_line`) — is a guaranteed
// use of freed memory. Seeding the verification walk only with the
// carried Moved state (definite, not MaybeMoved) keeps it
// false-positive-free, exactly like the straight-line move rule.
@ bck_loop i lo i hi s pre s cond_reads i cond_line → s {
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
    // Loop-carried verification. `back` is the converged body-exit
    // state; `verif` is the back-edge seed it implies. The condition is
    // re-evaluated before each body, so check its reads first, then
    // walk the body once more under the carried state.
    : s back ( bck_walk_seq lo hi head )
    : s verif ( bck_loop_carry_seed pre back )
    ( bck_check_moved_reads cond_reads cond_line verif )
    : s vend ( bck_walk_seq lo hi verif )
    ? != 0 ( nurl_str_len vend ) {} {}
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

// ── Borrow checker — escape analysis ───────────────────────────────
//
// A region is a scope frame; `g_bck_depth` (the borrowck
// block-nesting counter, maintained by bck_block_enter /
// bck_block_exit) names it — the function body is depth 1, every
// `?` / `~` / `??` / `{ }` block one deeper. An outer (shallower)
// region outlives every inner one; the caller outlives the whole
// function (conceptually depth 0).
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
// Known boundary: `*T` raw pointers stay unchecked (`*T` is NURL's
// `unsafe` FFI ABI), and a reference passed *through a helper
// function* needs an interprocedural summary — a per-function pass
// cannot see whether the callee retains it.

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

// Emit one borrow-checker `error:` as `file:line: error: <msg>`. The
// check fires parse-time but away from the offending token (after
// `gen_expr` has consumed the whole sub-expression), so — like
// `bck_diag` — it carries the source line explicitly and omits the
// caret rather than pointing at the wrong token. Increments
// `g_bck_errors`; main() exits non-zero at end of compile if any
// were recorded. The body is shared by escape, aliased-mut, and
// iterator-invalidation diagnostics.
@ bck_esc_warn i lex i line s msg → v {
    ( bck_emit_error ( nurl_lex_filename lex ) line msg )
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
                `' a value that references a more deeply scoped binding by pointer — it dangles once that inner scope exits` ) ) }
            {}
        } {}
    }
}

// A stack reference reaching `^`-return or an ownership-taking helper
// escapes the current frame unconditionally (the caller / a heap
// container / a worker thread all outlive every in-function region).
@ bck_esc_check_return i lex i syms i line s ident → v {
    ? & != g_borrowck 0 > ( bck_expr_refdepth syms ident ) 0
    { ( bck_esc_warn lex line `returning a value that references a stack binding by pointer — it dangles after this function returns (move the captured data to a heap-backed handle)` ) }
    {}
}

@ bck_esc_check_call_arg i lex i syms i line s ident s fname → v {
    ? & != g_borrowck 0 > ( bck_expr_refdepth syms ident ) 0
    { ( bck_esc_warn lex line ( nurl_str_cat3
        `passing a value that references a stack binding by pointer to '` fname
        `' — it escapes the current stack frame and dangles (move it to a heap-backed handle)` ) ) }
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
    // Record this statement's start line + col for gen_ident's cascade-aware
    // "unexpected token" diagnostic and for die_stmt (see g_stmt_line).
    = g_stmt_line bck_line
    = g_stmt_col ( nurl_lex_col lex )
    = g_stmt_bare_lit 0
    // A statement is a legal `^` position — clear any operand-context
    // guard inherited from an enclosing expression (e.g. a `?`/`??` arm
    // that descends back into statements).
    = g_ret_forbidden 0
    : s gs_rv ? == tt TT_COLON ( gen_let_or_struct lex syms cg )
    ? == tt TT_EQ ( gen_assign lex syms cg )
    ? == tt TT_TILDE ( gen_loop lex syms cg )
    ? == tt TT_SEMICOL ( gen_defer lex syms cg )
    {  // Bare expression in statement position. Record a `call`-shaped
        // statement only for a parenthesised call `( fn ... )`; `?` / `??`
        // control flow is captured by the gen_block_ret depth markers
        // instead, so it is not double-recorded here.
        // Bare-identifier-as-statement (critic v0.9.0 §1): if the leading
        // token is a name registered in syms with NO `__ptr` (i.e. not a
        // local/parameter) and NO `__global` (i.e. not a const / enum
        // variant), it is some kind of callable — @-fn, generic @-fn,
        // FFI fn, or runtime builtin. The user almost certainly forgot
        // the parens: calls in NURL are '( fn args )', not 'fn args'. A
        // bare callable name as a statement compiles to a dead name
        // lookup whose value is discarded — grammar-legal, semantically
        // useless. Die rather than warn: there is no legitimate program
        // shape this matches.
        ? == tt TT_IDENT
        { : s __bc_nm ( nurl_lex_val lex )
            : s __bc_ty ( nurl_sym_get syms __bc_nm )
            : s __bc_ptr ( nurl_sym_get syms ( nurl_str_cat __bc_nm `__ptr` ) )
            : s __bc_glb ( nurl_sym_get syms ( nurl_str_cat __bc_nm `__global` ) )
            : s __bc_par ( nurl_sym_get syms ( nurl_str_cat __bc_nm `__param` ) )
            ? & & & != 0 ( nurl_str_len __bc_ty )
            == 0 ( nurl_str_len __bc_ptr )
            == 0 ( nurl_str_len __bc_glb )
            == 0 ( nurl_str_len __bc_par )
            { ( die lex ( nurl_str_cat3
                `bare identifier '` __bc_nm
                `' as a statement has no effect — calls in NURL are written '( name args )', not 'name args'. Did you forget the parens?` ) ) }
            {} }
        {}
        : s bck_ev ( gen_expr lex syms cg )
        ? == tt TT_LPAREN { ( bck_record `expr` `` bck_line ) } {}
        bck_ev
    }
    // A `:` declaration is a STATEMENT — it must not type the enclosing
    // block/arm as value-producing. gen_let_or_struct leaves the RHS's
    // type in last_type as a side effect; an arm whose LAST statement is
    // a decl then looked value-typed to gen_cond/gen_match, which (a)
    // suppressed the Phase 2D arm-local fall-through drop ("value may
    // flow to the phi consumer") — leaking the binding — and (b) emitted
    // a bogus phi over the discarded decl value. `=` assignment is NOT
    // reset here: gen_assign publishes the LHS type deliberately (its
    // store_val legitimately feeds `?? r { F e → { = rc e } }`-shaped
    // arm phis; see gen_assign's tail comment).
    ? == tt TT_COLON { ( nurl_set_last_type `void` ) } {}
    // Borrow checker (Phase 1): drain this statement's move stash into
    // `move` rows — placed AFTER the statement's own record so the
    // consuming call itself reads the binding while still Owned.
    ( bck_flush_moves )
    // Flag a bare numeric/string literal statement for the block iterator's
    // dangling-operand check. A statement whose LEADING token is a literal
    // is, under prefix notation, exactly a bare literal (operators lead
    // their operands), so this is robust against nested blocks overwriting
    // the flag mid-parse. See g_stmt_bare_lit.
    = g_stmt_bare_lit ? | | == tt TT_INT == tt TT_FLOAT == tt TT_STR 1 0
    // Flag a non-call value-producing statement for the block iterator's
    // dead-value warning (see g_stmt_bare_value). Computed from this
    // statement's own leading token + final last_type, overwriting
    // whatever nested blocks set mid-parse. Calls (effects), `?`/`??`
    // (their arms may be effectful calls), and the void-publishing
    // statement forms (`:`/`=`/`~`/`;`) are excluded; literals carry
    // their own harder diagnostic and are excluded to keep it single.
    // The flag carries the dead statement's own LINE (not just 1): by
    // the time the block iterator reads it, lex already points at the
    // NEXT statement, so the diagnostic embeds the real line instead
    // of blaming the innocent neighbour.
    = g_stmt_bare_value ? ( __stmt_is_bare_value tt ( nurl_get_last_type ) ) bck_line 0
    gs_rv
}

// True when a statement with leading token `tt` whose generation left
// `lt` in last_type is a dead value expression: not a declaration /
// assignment / loop / defer / call / conditional / match / literal,
// and the produced type is non-void.
@ __stmt_is_bare_value i tt s lt → b {
    ? | | | == tt TT_COLON == tt TT_EQ == tt TT_TILDE == tt TT_SEMICOL
    { ^ F } {}
    ? | | == tt TT_LPAREN == tt TT_QUEST == tt TT_QUESTQUEST
    { ^ F } {}
    ? | | == tt TT_INT == tt TT_FLOAT == tt TT_STR
    { ^ F } {}
    ^ ! ( seq lt `void` )
}

// Soft check for the same-line shadow pattern: a `:` binding declares
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
    { ( warn lex ( nurl_str_cat3 `'` name `' shadows the enclosing function's parameter - rename` ) ) }
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
    // `: ~ * T name init` (mutable pointer to T)
    // miscompiles in long-running write loops — confirmed via the CSV
    // P2c hoist attempt where writes started segfaulting at ~row 66k.
    // Warn (don't `die`) because trivial isolated cases work and the
    // warning is advisory; suggest the immutable `: *T` alternative
    // or re-fetching the pointer per iteration.
    ? & is_mutable == ( nurl_lex_type lex ) TT_STAR
    { ( warn lex `mutable pointer binding ': ~ *T' miscompiles in long-running write loops. Prefer immutable ': *T' + re-fetch on grow, or carry the address as an i64 and cast per use.` ) }
    {}
    // Check if first token could be a type name by looking it up in symbol table
    ? & == ( nurl_lex_type lex ) TT_IDENT == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_lex_val lex ) ) )
    {  // Type inference: plain IDENT that's not a known type
        : s name ( nurl_lex_val lex )
        ( __warn_if_shadows_param lex syms name )
        ( lint_note_bind lex name )
        ( nurl_lex_advance lex )
        : b rhs_is_slice_lit == ( nurl_lex_type lex ) TT_LBRACK
        // Borrow checker (Phase 2): snapshot the RHS's first token —
        // a bare identifier RHS is a binding-to-binding alias copy.
        : i bck_rhs_tt ( nurl_lex_type lex )
        : s bck_rhs_val ( nurl_lex_val lex )
        ( nurl_sym_def syms `__last_call_ret_owned__` `` )
        ( nurl_sym_def syms `__last_agg_owned_fields__` `` )
        ( nurl_sym_def syms `__last_call_ret_struct_fields__` `` )
        ( nurl_sym_def syms `__last_expr_refdepth__` `` )
        ( nurl_sym_def syms `__last_value_borrow__` `` )
        ( nurl_sym_def syms `__last_closure_env__` `` )
        : s val ( gen_expr lex syms cg )
        : s vt ( nurl_get_last_type )
        // Closure-env reclamation (§7.4): did the RHS allocate a capturing
        // closure's env? Captured now, registered for the function-exit
        // free after the binding is recorded below.
        : s rhs_closure_env ( nurl_sym_get syms `__last_closure_env__` )
        // Borrow provenance: did the RHS produce a borrow (a value aliasing
        // something the caller still owns)? If so, an auto-Drop binding here
        // must NOT register its drop — the owner reclaims it.
        : s rhs_borrow ( nurl_sym_get syms `__last_value_borrow__` )
        // Borrow checker: record this binding (inference path).
        ( bck_record `let` name bck_line )
        ( bck_let_alias syms is_mutable bck_rhs_tt bck_rhs_val vt bck_line )
        : b rhs_is_owned_call != 0 ( nurl_str_len ( nurl_sym_get syms `__last_call_ret_owned__` ) )
        // Escape analysis: stamp this binding's
        // region (block depth) and, when the initialiser was a stack
        // reference — a closure literal capturing a binding by
        // pointer, an aggregate holding one, or a copy of such a
        // binding — its referent depth, so gen_ret / gen_assign /
        // gen_call reject escapes (docs/MEMORY.md §2.3).
        ( bck_esc_let syms name ( bck_expr_refdepth syms
        ? ( is_ident_tok bck_rhs_tt ) bck_rhs_val `` ) )
        : s ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ptr )
        ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print `\n` )
        ( nurl_print `  store ` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print ` ` )
        ( nurl_print val ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty vt ) )
        ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
        ( dbg_declare_local name ptr vt ( nurl_lex_line lex ) 0 syms )
        ( nurl_sym_def syms name vt )
        ( rec_decl_loc syms name bck_line lex )
        ( nurl_sym_def syms ( nurl_str_cat name `__ptr` ) ptr )
        // Only mark mutability if explicitly specified with ~
        ? is_mutable
        { ( nurl_sym_def syms ( nurl_str_cat name `__mutable` ) `1` ) }
        {}
        ? | rhs_is_slice_lit & rhs_is_owned_call ( mem_is_slice_ty vt )
        { ( mem_own_add syms name ) ( mem_journal_push_slice cg vt ptr ) }
        {}
        // Closure-env reclamation (§7.4): a `: f \ … x …` literal binding
        // owns the env → track it for the function-exit free. A `: g f`
        // copy MOVES the env to g (the borrow checker forbids reusing f),
        // so transfer the registration rather than tracking both.
        ? != 0 ( nurl_str_len rhs_closure_env )
        { ( mem_own_closure_add syms name ) }
        { ? & ( is_ident_tok bck_rhs_tt )
            ( str_contains_word ( nurl_sym_get syms `__owned_closure_envs__` ) bck_rhs_val )
            { ( mem_own_closure_remove syms bck_rhs_val ) ( mem_own_closure_add syms name ) }
            {} }
        // Phase 2B: string ownership tracking (opt-in)
        ? != 0 g_auto_drop_strings
        { ? & ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` ) ( seq ( nurl_llty vt ) `i8*` )
            { ( mem_own_add_str syms ptr ) ( mem_journal_push_str cg ptr ) }
            {}
        }
        {}
        // Phase 2C: struct-field ownership — if RHS was `@ T { ... }` and one
        // or more fields came from a fresh allocating i8* call, register a
        // drop for each such field tied to this binding's alloca. A4c: a
        // struct-returning CALL RHS routes its transferred fields through
        // the same registration.
        ( __propagate_call_struct_fields syms )
        ? != 0 g_auto_drop_strings
        { ( mem_register_agg_owned_fields syms ptr vt )
            ( mem_journal_push_agg_fields syms cg ptr ) }
        {}
        // Phase 2D: User Drop trait. A COMPILER-auto Drop is skipped when
        // the RHS is a borrow (vec_get / a ret_borrow accessor) — dropping
        // it would double-free the container that still owns the value. The
        // binding inherits `__borrow` so it propagates further.
        ? & & != 0 g_auto_drop_strings ( __is_autodrop_enum vt syms ) != 0 ( nurl_str_len rhs_borrow )
        { ( nurl_sym_def syms ( nurl_str_cat name `__borrow` ) `1` ) }
        { ? != 0 g_auto_drop_strings
            { : s impl_key ( nurl_str_cat `drop##` vt )
                : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
                ? != 0 ( nurl_str_len impl_mangle_key )
                { ( mem_own_add_user_drop syms ptr vt ) ( mem_journal_push_userdrop syms cg ptr vt ) }
                {}
            }
            {} }
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
            ( __warn_if_shadows_param lex syms name )
            ( lint_note_bind lex name )
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
            // ALSO stash the LLVM form of T so gen_match can reconstruct
            // single-pointer-handle structs (Vec/String/Channel/Thread)
            // whose NURL source is a parenthesised compound like
            // `( Vec u )` — `inner_t` above is just `(` in that case
            // and won't look up to anything useful.
            : s let_res_t_llvm ( nurl_sym_get g_res_type_syms `__last_res_t_llvm__` )
            ? != 0 ( nurl_str_len let_res_t_llvm )
            { ( nurl_sym_def syms ( nurl_str_cat name `__res_t_llvm` ) let_res_t_llvm ) }
            {}
            // Same for E, so a bound `?? r { F e → e }` with a bare-pointer
            // error type reconstructs the F-arm payload (enum E resolves by
            // its NURL name and doesn't reach this fallback).
            : s let_res_e_llvm ( nurl_sym_get g_res_type_syms `__last_res_err_llvm__` )
            ? != 0 ( nurl_str_len let_res_e_llvm )
            { ( nurl_sym_def syms ( nurl_str_cat name `__res_e_llvm` ) let_res_e_llvm ) }
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
                ( nurl_sym_def syms `__last_call_ret_struct_fields__` `` )
                ( nurl_sym_def syms `__last_expr_refdepth__` `` )
                ( nurl_sym_def syms `__last_value_borrow__` `` )
                ( nurl_sym_def syms `__last_closure_env__` `` )
                : s val ( gen_expr lex syms cg )
                : s vt ( nurl_get_last_type )
                : s rhs_closure_env ( nurl_sym_get syms `__last_closure_env__` )
                // Thread-safety: when the RHS is a closure that captured a
                // non-Send value (an Rc), carry it onto this binding so a later
                // `( thread_spawn name )` can reject it. Gated on the RHS being
                // a closure so a non-closure binding never inherits a stale flag.
                ? & != 0 ( nurl_str_len rhs_closure_env ) != 0 ( nurl_str_len g_last_closure_nonsend )
                { ( nurl_sym_def syms ( nurl_str_cat name `__closure_nonsend` ) g_last_closure_nonsend ) }
                {}
                // A `String` binding cannot be initialised from a raw
                // string literal / i8* — a String OWNS a heap control
                // block + buffer, whereas a literal is a borrowed i8*.
                // Storing the i8* into the %String slot used to emit IR
                // that only clang rejected ("ptr but expected %String");
                // diagnose it here with the canonical cure. (coerce_store_val
                // deliberately won't insertvalue-wrap an i8* as a String —
                // that would alias a literal as a control block and crash.)
                ? & ( seq ptype `%String` ) | ( seq ( nurl_llty vt ) `i8*` ) ( seq vt `sref` )
                { ( die lex `cannot initialise a 'String' binding from a raw string literal / i8* — a String owns a heap buffer, not a borrowed pointer. Wrap it with ( string_from ... ), or use ( string_new ) for empty.` ) }
                {}
                // Borrow provenance (typed path): a borrow RHS must not
                // register an auto-Drop — the owner reclaims it.
                : s rhs_borrow ( nurl_sym_get syms `__last_value_borrow__` )
                // Borrow checker: record this binding (typed path).
                ( bck_record `let` name bck_line )
                ( bck_let_alias syms is_mutable bck_rhs_tt bck_rhs_val vt bck_line )
                : b rhs_is_owned_call != 0 ( nurl_str_len ( nurl_sym_get syms `__last_call_ret_owned__` ) )
                // Escape analysis: stamp region +
                // referent depth — see the type-inference path above.
                ( bck_esc_let syms name ( bck_expr_refdepth syms
                ? ( is_ident_tok bck_rhs_tt ) bck_rhs_val `` ) )

                // Widen i1 short-circuit / comparison results to the declared
                // integer width before storing (`: i can_l & …` etc.).
                : s widened_val ( coerce_store_val lex val vt ptype syms cg )
                // Handle closure to function pointer conversion
                : s store_val ( convert_closure_arg widened_val vt ptype cg )

                : s ptr ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print ptr )
                ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty ptype ) ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty ptype ) ) ( nurl_print ` ` )
                ( nurl_print store_val ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty ptype ) )
                ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
                ( dbg_declare_local name ptr ptype ( nurl_lex_line lex ) 0 syms )
                ( nurl_sym_def syms name ptype )
                ( rec_decl_loc syms name bck_line lex )
                ( nurl_sym_def syms ( nurl_str_cat name `__ptr` ) ptr )
                // Only mark mutability if explicitly specified with ~
                ? is_mutable
                { ( nurl_sym_def syms ( nurl_str_cat name `__mutable` ) `1` ) }
                {}
                ? | rhs_is_slice_lit & rhs_is_owned_call ( mem_is_slice_ty ptype )
                { ( mem_own_add syms name ) ( mem_journal_push_slice cg ptype ptr ) }
                {}
                // Closure-env reclamation (§7.4): track a capturing closure
                // bound here for the function-exit free.
                ? != 0 ( nurl_str_len rhs_closure_env )
                { ( mem_own_closure_add syms name ) }
                {}
                // Phase 2B: string ownership tracking (opt-in)
                ? != 0 g_auto_drop_strings
                { ? & ( seq ( nurl_sym_get syms `__last_call_ret_owned__` ) `str` ) ( seq ( nurl_llty ptype ) `i8*` )
                    { ( mem_own_add_str syms ptr ) ( mem_journal_push_str cg ptr ) }
                    {}
                }
                {}
                // Phase 2C: struct-field ownership (see type-inference path).
                // A4c: bridge a struct-returning CALL RHS into the same path.
                ( __propagate_call_struct_fields syms )
                ? != 0 g_auto_drop_strings
                { ( mem_register_agg_owned_fields syms ptr ptype )
                    ( mem_journal_push_agg_fields syms cg ptr ) }
                {}
                // Phase 2D: User Drop trait. Skip a COMPILER-auto Drop when
                // the RHS is a borrow (would double-free the owner); mark the
                // binding `__borrow` so it propagates.
                ? & & != 0 g_auto_drop_strings ( __is_autodrop_enum ptype syms ) != 0 ( nurl_str_len rhs_borrow )
                { ( nurl_sym_def syms ( nurl_str_cat name `__borrow` ) `1` ) }
                { ? != 0 g_auto_drop_strings
                    { : s impl_key ( nurl_str_cat `drop##` ptype )
                        : s impl_mangle_key ( nurl_sym_get g_impl_name_syms impl_key )
                        ? != 0 ( nurl_str_len impl_mangle_key )
                        { ( mem_own_add_user_drop syms ptr ptype ) ( mem_journal_push_userdrop syms cg ptr ptype ) }
                        {}
                    }
                    {} }
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
        // Mutability enforcement. A binding introduced with `:` (and no
        // `~`) is immutable; `= name expr` targeting it is a compile
        // error. Mutability is opt-in and recorded as `<name>__mutable`
        // at the declaration site — `: ~` locals/globals and `~`/inout
        // parameters all set it. We only fire for a *known* binding (its
        // type `vt` is recorded), so unknown / forward names fall
        // through to the normal undefined-symbol path instead of a
        // misleading immutability error.
        : s mut_check ( nurl_sym_get syms ( nurl_str_cat name `__mutable` ) )
        : s vt ( nurl_sym_get syms name )
        : s ptr ( nurl_sym_get syms ( nurl_str_cat name `__ptr` ) )
        : s glb ( nurl_sym_get syms ( nurl_str_cat name `__global` ) )
        : s param_check ( nurl_sym_get syms ( nurl_str_cat name `__param` ) )
        ? & != 0 ( nurl_str_len vt ) == 0 ( nurl_str_len mut_check )
        {  // known binding, declared immutable. Point the diagnostic at
            // the declaration (recorded via rec_decl_loc) so the author
            // knows exactly where to add `~`.
            : s dfile ( nurl_sym_get syms ( nurl_str_cat name `__declfile` ) )
            : s dline ( nurl_sym_get syms ( nurl_str_cat name `__declline` ) )
            : s where ? != 0 ( nurl_str_len dline )
            ( nurl_str_cat3 ` (declared at ` ( nurl_str_cat3 dfile `:` dline ) `; add ': ~' there to make it mutable)` )
            ``
            : s kind ? != 0 ( nurl_str_len param_check ) `parameter`
            ? != 0 ( nurl_str_len glb ) `global` `variable`
            ( die lex ( nurl_str_cat3 ( nurl_str_cat `cannot assign to immutable ` kind ) ( nurl_str_cat `: ` name ) where ) )
        }
        {}
        // Silent-snapshot footgun: assigning to a binding the enclosing
        // closure captured BY VALUE. The write lands on a fresh per-invocation
        // local copy — it neither persists across calls (each invocation
        // re-snapshots the captured value) nor reaches the original binding.
        // The closure-counter `: ~ i n  ^ \ → i { = n + n 1  ^ n }` returns
        // 1,1,1 instead of 1,2,3 because of this. By design, scalars (and
        // single-field handles) capture by value; only a `: ~` MULTI-FIELD
        // struct captures by reference — and that shared form is a stack
        // reference that cannot escape its frame. So there is no escaping
        // mutable-state closure: surface the dead store instead of emitting it
        // silently. Non-fatal (the read/scratch use within one call is valid).
        ? != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat name `__captured_byval` ) ) )
        { ( warn lex ( nurl_str_cat3
            `assignment to '` name
            `' is discarded when the closure returns — it was captured by value (a snapshot), so writes do not persist across invocations or reach the captured binding. For shared mutable state use a ': ~' multi-field struct captured by reference (which cannot escape the defining frame); an escaping mutable-state closure is not supported.` ) ) }
        {}
        // Phase 2B reassignment-drop: if the LHS is an owned i8* binding and
        // the RHS is a fresh allocating call, free the old value before
        // overwriting. We gate on RHS being a fresh owned-call (not an alias
        // load) to avoid double-free / use-after-free when the user writes
        // `= x y` where y aliases x's heap.
        : b lhs_is_owned_str & & != 0 g_auto_drop_strings
        ( seq ( nurl_llty vt ) `i8*` )
        ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) ptr )
        ? lhs_is_owned_str { ( nurl_sym_def syms `__last_call_ret_owned__` `` ) } {}
        // Escape analysis: snapshot the RHS's
        // first token (a bare identifier may copy a stack reference)
        // and clear the side-channel a closure / aggregate literal
        // RHS would publish.
        : i bck_rhs_tt ( nurl_lex_type lex )
        : s bck_rhs_val ( nurl_lex_val lex )
        ( nurl_sym_def syms `__last_expr_refdepth__` `` )
        : s val ( gen_operand lex syms cg )
        : s __asn_rt ( nurl_get_last_type )
        // Type-agreement on reassignment (the store dual of the let-binding
        // / call-arg checks): a never-legal clash (float-vs-non-float, a
        // different named struct by value, or String vs raw C-string) would
        // otherwise emit a mismatched `store` clang rejects. Width / sign /
        // pointer coercions stay legal and are not flagged.
        ? ( __store_type_clash __asn_rt vt )
        { ( die_stmt lex ( nurl_str_cat
            ( nurl_str_cat4 `cannot assign a value of type '` __asn_rt `' to '` name )
            ( nurl_str_cat3 `' of type '` vt `' — NURL has no implicit conversions` ) ) ) }
        {}
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
        // Ownership transfer: `= name x` with a bare-identifier RHS
        // copies x's pointer into `name`. If x was a tracked owned
        // string, cancel ITS scheduled drop — the buffer lives on
        // through `name` now (whose own registration, if any, frees it
        // exactly once at scope exit). Without this, the arm/loop
        // delta-drop frees x while `name` still aliases it.
        ? & & != 0 g_auto_drop_strings ( seq ( nurl_llty vt ) `i8*` ) ( is_ident_tok bck_rhs_tt )
        { ( mem_remove_owned_str syms
            ( nurl_sym_get syms ( nurl_str_cat bck_rhs_val `__ptr` ) ) ) }
        {}
        // Same for a moved user `% Drop` binding: `= name x` transfers x's
        // value into name, so x is no longer dropped — forget its
        // alloca-keyed journal entry or a panic would replay its
        // destructor on a value the destination now owns (§7).
        ? & & != 0 g_auto_drop_strings ( is_ident_tok bck_rhs_tt )
        ( str_contains_word ( nurl_sym_get syms `__user_drops__` )
        ( nurl_sym_get syms ( nurl_str_cat bck_rhs_val `__ptr` ) ) )
        { ( mem_journal_forget_userdrop cg
            ( nurl_sym_get syms ( nurl_str_cat bck_rhs_val `__ptr` ) )
            ( nurl_sym_get syms bck_rhs_val ) ) }
        {}
        // Closure-env reclamation (§7.4): `= name f` moves f's closure (and
        // env) into name — f is no longer this frame's to free at scope
        // exit (name, or whatever name escapes into, owns it now).
        ? & ( is_ident_tok bck_rhs_tt )
        ( str_contains_word ( nurl_sym_get syms `__owned_closure_envs__` ) bck_rhs_val )
        { ( mem_own_closure_remove syms bck_rhs_val ) }
        {}
        // Widen i1 short-circuit / comparison results to the LHS's
        // declared integer width, so `= myi64 & a b` stores cleanly.
        : s rhs_ty ( nurl_get_last_type )
        : s store_val ( coerce_store_val lex val rhs_ty vt syms cg )
        ? != 0 ( nurl_str_len ptr )
        { ( nurl_print `  store ` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print ` ` )
            ( nurl_print store_val ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty vt ) )
            ( nurl_print `* ` ) ( nurl_print ptr ) ( nurl_print `\n` )
        }
        { ? != 0 ( nurl_str_len glb )
            { ( nurl_print `  store ` ) ( nurl_print ( nurl_llty vt ) ) ( nurl_print ` ` )
                ( nurl_print store_val ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty vt ) )
                ( nurl_print `* @` ) ( nurl_print name ) ( nurl_print `\n` )
            }
            {}
        }
        // Panic-unwind journal: assigning an owned struct into a by-ref
        // capture escapes it to the caller's frame. Forget its heap leaves
        // so a later panic's drain does not free what the caller now owns
        // (docs/MEMORY.md §7). Gated on a struct LHS that is a by-ref
        // capture; a harmless no-op otherwise.
        ? & & != 0 g_auto_drop_strings
        == ( nurl_str_get vt 0 ) 37
        != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat name `__captured_byref` ) ) )
        { ( mem_journal_forget_struct syms cg store_val vt ) }
        {}
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

    // Slice aggregate "{ T*, i64 }": extract data ptr, then GEP + store.
    // Must NOT match a pointer-to-aggregate "{ … }*" (e.g. an option-
    // element backing store `{ i1, %String }*`): those end in `*` and
    // belong to the pointer-index path below, which strips the `*` and
    // GEPs over the aggregate element directly.
    ? & == ( nurl_str_get pt 0 ) 123 != ( nurl_str_get pt - ( nurl_str_len pt ) 1 ) 42
    { : i ptlen ( nurl_str_len pt )
        : s ptr_ty ( nurl_str_slice pt 2 - - ptlen 7 2 )
        : s elem_ty ( nurl_str_slice ptr_ty 0 - ( nurl_str_len ptr_ty ) 1 )
        : s data_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print data_ptr )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty pt ) )
        ( nurl_print ` ` ) ( nurl_print pv ) ( nurl_print `, 0\n` )
        ? == ( nurl_lex_type lex ) TT_INT
        { : i idx ( nurl_lex_inum lex )
            ( nurl_lex_advance lex )
            : s rhs ( gen_expr lex syms cg )
            : s gep ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print gep )
            ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_ty ) )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty ptr_ty ) )
            ( nurl_print ` ` ) ( nurl_print data_ptr )
            ( nurl_print `, i32 ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
            ( nurl_print `  store ` ) ( nurl_print ( nurl_llty elem_ty ) )
            ( nurl_print ` ` ) ( nurl_print rhs )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem_ty ) )
            ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
            ^ rhs
        }
        { : s idx_val ( gen_expr lex syms cg )
            : s idx_type ( nurl_get_last_type )
            : s rhs ( gen_expr lex syms cg )
            : s gep ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print gep )
            ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_ty ) )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty ptr_ty ) )
            ( nurl_print ` ` ) ( nurl_print data_ptr )
            ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
            ( nurl_print `  store ` ) ( nurl_print ( nurl_llty elem_ty ) )
            ( nurl_print ` ` ) ( nurl_print rhs )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem_ty ) )
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
            ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_type ) )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt ) )
            ( nurl_print ` ` ) ( nurl_print pv )
            ( nurl_print `, i32 ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
            ( nurl_print `  store ` ) ( nurl_print ( nurl_llty elem_type ) )
            ( nurl_print ` ` ) ( nurl_print rhs )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem_type ) )
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
                {  // Struct pointer "%T*": the next token is either a field
                    // name or a variable used as an array index (e.g.
                    // `= . data idx x` where data: *Match and idx is the index
                    // var). The rule (see `field_wins` below) mirrors the read
                    // path: a name that IS a field of this concrete struct wins
                    // and stores into that field; the value-as-index array store
                    // is taken only when the name is NOT a field — raw pointers,
                    // or a tparam element type whose field lookup is suppressed
                    // (how `stdlib/core/vec.nu` writes its elements).
                    : i stlen ( nurl_str_len st )
                    : s sname ( nurl_str_slice st 1 - stlen 1 )
                    : s fname ( nurl_lex_val lex )
                    // Tparam-substituted element type → no source-accessible
                    // fields (opaque type variable in the generic); suppress
                    // the field lookup so `= . data idx x` stores into the
                    // array element, matching the read path in gen_member.
                    : s fidx_s ? ( str_contains_word g_mono_tparam_tys sname ) `` ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
                    : b is_field_ident ( is_ident_tok ( nurl_lex_type lex ) )
                    : b is_field_match & is_field_ident != 0 ( nurl_str_len fidx_s )
                    // A concrete struct field ALWAYS wins over a same-named
                    // in-scope variable — param OR local — symmetric with the
                    // read path in gen_member ("a struct field ALWAYS wins").
                    // Array-indexing a struct pointer BY a field name is never
                    // the intent; the value-as-index store below is reached only
                    // when the IDENT is NOT a field of this struct: raw pointers,
                    // or a tparam element type whose field lookup is suppressed
                    // above (stdlib/core/vec.nu's element writes). Previously the
                    // field only won when it was ALSO shadowed by a parameter, so
                    // `= . t lo lo` with a non-param local `lo` matching field
                    // `lo` silently compiled to `t[lo] = lo` (value-as-index) —
                    // a struct-corrupting miscompile with no diagnostic.
                    : b field_wins is_field_match
                    : s var_t ( nurl_sym_get syms fname )
                    ? & ! field_wins > ( int_width var_t ) 0
                    {  // IDENT is an integer variable (and not a param
                        // shadowing a field) — array-style store *T[idx] = rhs.
                        : s idx_val ( gen_expr lex syms cg )
                        : s idx_type ( nurl_get_last_type )
                        : s rhs ( gen_expr lex syms cg )
                        : s gep ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print gep )
                        ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty st ) )
                        ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt ) )
                        ( nurl_print ` ` ) ( nurl_print pv )
                        ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                        ( nurl_print `  store ` ) ( nurl_print ( nurl_llty st ) )
                        ( nurl_print ` ` ) ( nurl_print rhs )
                        ( nurl_print `, ` ) ( nurl_print ( nurl_llty st ) )
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
                            ? ( __store_type_clash ( nurl_get_last_type ) ftype )
                            { ( die lex ( nurl_str_cat ( nurl_str_cat4
                                `cannot store a value of type '` ( nurl_get_last_type ) `' into field '` fname )
                                ( nurl_str_cat3 `' of type '` ftype `' — NURL has no implicit conversions` ) ) ) }
                            {}
                            : s gep ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print gep )
                            ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty st ) )
                            ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt ) )
                            ( nurl_print ` ` ) ( nurl_print pv )
                            ( nurl_print `, i32 0, i32 ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
                            ( nurl_print `  store ` ) ( nurl_print ( nurl_llty ftype ) )
                            ( nurl_print ` ` ) ( nurl_print rhs )
                            ( nurl_print `, ` ) ( nurl_print ( nurl_llty ftype ) )
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
                                ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty st ) )
                                ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt ) )
                                ( nurl_print ` ` ) ( nurl_print pv )
                                ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty st ) )
                                ( nurl_print ` ` ) ( nurl_print rhs )
                                ( nurl_print `, ` ) ( nurl_print ( nurl_llty st ) )
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
                    ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty st ) )
                    ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt ) )
                    ( nurl_print ` ` ) ( nurl_print pv )
                    ( nurl_print `, ` ) ( nurl_print idx_type ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                    ( nurl_print `  store ` ) ( nurl_print ( nurl_llty st ) )
                    ( nurl_print ` ` ) ( nurl_print rhs )
                    ( nurl_print `, ` ) ( nurl_print ( nurl_llty st ) )
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
                ? ( __store_type_clash ( nurl_get_last_type ) ftype )
                { ( die lex ( nurl_str_cat ( nurl_str_cat4
                    `cannot store a value of type '` ( nurl_get_last_type ) `' into field '` fname )
                    ( nurl_str_cat3 `' of type '` ftype `' — NURL has no implicit conversions` ) ) ) }
                {}
                : s gep ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print gep )
                ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty pt ) )
                ( nurl_print `, ` ) ( nurl_print pt_ptr )
                ( nurl_print ` ` ) ( nurl_print alloca_ptr )
                ( nurl_print `, i32 0, i32 ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty ftype ) )
                ( nurl_print ` ` ) ( nurl_print rhs )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty ftype ) )
                ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                ^ rhs
            }
        }
    }
}

// ── Cast # type expr ───────────────────────────────────────────────

// int_width: LLVM integer type string → bit width, or 0 if not iN.
// Reconstruct a float (`double` / f32 `float`) enum payload out of the
// uniform i64 enum slot. The construction side (gen_agg_lit) bitcast the
// float to a same-width int into the slot; this is the exact inverse:
// bitcast the i64 slot back (an f32 first truncs to i32). `cv` is the
// already-allocated destination register.
@ emit_enum_float_extract s cv s pt s pr i cg → v {
    ? ( seq pt `double` )
    { ( nurl_print `  ` ) ( nurl_print cv )
        ( nurl_print ` = bitcast i64 ` ) ( nurl_print pr ) ( nurl_print ` to double\n` ) }
    { : s b32 ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print b32 )
        ( nurl_print ` = trunc i64 ` ) ( nurl_print pr ) ( nurl_print ` to i32\n` )
        ( nurl_print `  ` ) ( nurl_print cv )
        ( nurl_print ` = bitcast i32 ` ) ( nurl_print b32 ) ( nurl_print ` to float\n` ) }
}

// True iff an LLVM type string is a float type (`double` or f32 `float`).
@ is_float_ty s ty → b { ^ | ( seq ty `double` ) ( seq ty `float` ) }

// A never-legal store/assign type clash between a value's LLVM type `vt`
// and the declared destination type `dt`: float-vs-non-float, a different
// named struct by value, or String vs raw C-string. Integer width /
// signedness / pointer-stash coercions are legal and NOT flagged. Shared
// by gen_assign (reassignment) and gen_field_store (field writes).
@ __store_type_clash s vt s dt → b {
    ? | == 0 ( nurl_str_len vt ) == 0 ( nurl_str_len dt ) { ^ F } {}
    ^ | | != ( is_float_ty vt ) ( is_float_ty dt )
    ( __arg_named_struct_mismatch vt dt ) ( __arg_str_cstr_mismatch vt dt )
}

// Map a SOURCE-spelling scalar token to its canonical sized-int type
// ("" when the token is not a sized-int scalar). Used by the call-arg
// width coercion, where the declared parameter type is the pre-pass
// source string (`u`, `u16`, `i`, …) rather than an LLVM type.
@ src_int_ty s t → s {
    ? ( seq t `u` ) `u8`
    ? ( seq t `u8` ) `u8`
    ? ( seq t `u16` ) `u16`
    ? ( seq t `u32` ) `u32`
    ? ( seq t `u64` ) `u64`
    ? ( seq t `i8` ) `i8`
    ? ( seq t `i16` ) `i16`
    ? ( seq t `i32` ) `i32`
    ? ( seq t `i64` ) `i64`
    ? ( seq t `i` ) `i64`
    ``
}

// Emit an integer-width bridge `%r = trunc|sext|zext <from> <val> to
// <to>` and return the new register; used by BOTH call-arg coercion
// sites (FFI + NURL callee) so the widen/narrow logic lives once. Widen
// direction follows the SOURCE type (A1: an unsigned u8/u16/u32
// zero-extends). Caller updates its own arg-type to `to_ty` after.
@ __emit_iwiden i cg s val s from_ty s to_ty → s {
    : s r ( nurl_cg_reg cg )
    : s ins ? > ( int_width from_ty ) ( int_width to_ty ) ` = trunc `
    ? ( ty_is_unsigned from_ty ) ` = zext ` ` = sext `
    ( nurl_print `  ` ) ( nurl_print r ) ( nurl_print ins )
    ( nurl_print ( nurl_llty from_ty ) ) ( nurl_print ` ` ) ( nurl_print val )
    ( nurl_print ` to ` ) ( nurl_print ( nurl_llty to_ty ) ) ( nurl_print `\n` )
    ^ r
}

@ int_width s ty → i {
    ? ( seq ty `i1` ) 1
    ? ( seq ty `i8` ) 8
    ? ( seq ty `i16` ) 16
    ? ( seq ty `i32` ) 32
    ? ( seq ty `i64` ) 64
    // Unsigned internal scalars (A1) have the same widths.
    ? ( seq ty `u8` ) 8
    ? ( seq ty `u16` ) 16
    ? ( seq ty `u32` ) 32
    ? ( seq ty `u64` ) 64
    0
}

// An LLVM type string denotes a pointer iff it ends in `*` (e.g.
// `i8*`, `%Foo*`, `i8**`). Used by comparison codegen to coerce
// pointer operands to i64 before `icmp`, so `== ptr 0` / `!= ptr 0`
// null-checks and pointer↔pointer compares emit valid IR.
// Bind ONE enum payload slot (`pidx` ≥ 1; slot 0 keeps its own opt/res-bool
// reconstruction inline in gen_match). The payload rode the uniform i64
// enum slot; reconstruct it as the exact inverse of gen_agg_lit's boxing —
// float via emit_enum_float_extract, a narrow int via trunc, a
// single-pointer struct handle via inttoptr + insertvalue, a multi-field
// struct / enum / anon aggregate via a load through the heap-box pointer,
// i64 as-is, else a bare pointer via inttoptr. Then alloca + store +
// register the binding (with its `__ptr` metadata and any
// user-`Drop`). One call per slot, driven by a loop in gen_match,
// generalises the former hand-unrolled slot-1 / slot-2 blocks to N
// payloads — lifting the 3-payload destructuring limit.
@ emit_enum_payload_bind s pvi i pidx s pattern_name s match_type s match_val i syms i cg → v {
    : s pkey ( nurl_str_cat3 pattern_name `__payload__` ( nurl_str_int pidx ) )
    : s pti ( nurl_sym_get syms pkey )
    : s pri ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print pri )
    ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty match_type ) )
    ( nurl_print ` ` ) ( nurl_print match_val )
    ( nurl_print `, ` ) ( nurl_print ( nurl_str_int + pidx 1 ) ) ( nurl_print `\n` )
    : s cvi ( nurl_cg_reg cg )
    ? ( is_float_ty pti )
    { ( emit_enum_float_extract cvi pti pri cg ) }
    { ? & > ( int_width pti ) 0 < ( int_width pti ) 64 {
            ( nurl_print `  ` ) ( nurl_print cvi )
            ( nurl_print ` = trunc i64 ` ) ( nurl_print pri ) ( nurl_print ` to ` ) ( nurl_print ( nurl_llty pti ) ) ( nurl_print `\n` )
        } {
            : ~ b is_sh F
            : ~ s f0ty ``
            ? == ( nurl_str_get pti 0 ) 37
            { : s snamei ( nurl_str_slice pti 1 - ( nurl_str_len pti ) 1 )
                : s vlisti ( nurl_sym_get syms ( nurl_str_cat snamei `__variants` ) )
                ? == 0 ( nurl_str_len vlisti )
                { = f0ty ( nurl_sym_get syms ( nurl_str_cat3 snamei `__idx_0` `__type` ) )
                    ? & != 0 ( nurl_str_len f0ty )
                    == ( nurl_str_get f0ty - ( nurl_str_len f0ty ) 1 ) 42
                    { = is_sh T } {} }
                {} }
            {}
            ? is_sh
            { : s hip ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print hip )
                ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pri )
                ( nurl_print ` to ` ) ( nurl_print ( nurl_llty f0ty ) ) ( nurl_print `\n` )
                ( nurl_print `  ` ) ( nurl_print cvi )
                ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty pti ) )
                ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty f0ty ) )
                ( nurl_print ` ` ) ( nurl_print hip ) ( nurl_print `, 0\n` ) }
            { ? | == ( nurl_str_get pti 0 ) 123
                & == ( nurl_str_get pti 0 ) 37
                != ( nurl_str_get pti - ( nurl_str_len pti ) 1 ) 42
                { : s bip ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print bip )
                    ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pri ) ( nurl_print ` to ptr\n` )
                    ( nurl_print `  ` ) ( nurl_print cvi )
                    ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty pti ) )
                    ( nurl_print `, ptr ` ) ( nurl_print bip ) ( nurl_print `\n` ) }
                { ( nurl_print `  ` ) ( nurl_print cvi )
                    ? == ( int_width pti ) 64
                    { ( nurl_print ` = add i64 ` ) ( nurl_print pri ) ( nurl_print `, 0\n` ) }
                    { ( nurl_print ` = inttoptr i64 ` ) ( nurl_print pri ) ( nurl_print ` to i8*\n` ) } } }
        } }
    : s vpi ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print vpi )
    ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty pti ) ) ( nurl_print `\n` )
    ( nurl_print `  store ` ) ( nurl_print ( nurl_llty pti ) )
    ( nurl_print ` ` ) ( nurl_print cvi )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty pti ) )
    ( nurl_print `* ` ) ( nurl_print vpi ) ( nurl_print `\n` )
    ( nurl_sym_def syms pvi pti )
    ( nurl_sym_def syms ( nurl_str_cat pvi `__ptr` ) vpi )
    ? != 0 g_auto_drop_strings
    { : s akey ( nurl_str_cat `drop##` pti )
        ? & != 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms akey ) )
        == 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms ( nurl_str_cat `autodrop##` pti ) ) )
        { ( mem_own_add_user_drop syms vpi pti ) }
        {}
    }
    {}
}

@ is_ptr_ty s ty → b {
    : i n ( nurl_str_len ty )
    ? == n 0 { ^ F } {}
    ^ == ( nurl_str_get ty - n 1 ) 42
}

@ gen_cast i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    // The cast TARGET's signedness is in the parsed type itself (A1):
    // `# u …` yields dt = `u8`, and every integer-result return path
    // below sets the last type to dt, so an ENCLOSING widening cast /
    // binop / shift reads the right signedness straight off the type —
    // e.g. the inner `# u …` in `# i64 # u <expr>` makes the outer
    // widen a `zext`, not a `sext`, with no side-channel to clobber.
    : s dt ( parse_type lex )
    : b dst_unsigned ( ty_is_unsigned dt )
    // Diagnose `# T { ... }` parsing as cast-to-T applied to a
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
            tname ` { ... }' instead.` ) ) }
        {}
    }
    {}
    : s val ( gen_operand lex syms cg )
    : s st ( nurl_get_last_type )
    : s res ( nurl_cg_reg cg )
    // Detect pointer source/destination (LLVM type ends with '*')
    : i stlen ( nurl_str_len st )
    : i dtlen ( nurl_str_len dt )
    : b src_ptr == ( nurl_str_get st - stlen 1 ) 42
    : b dst_ptr == ( nurl_str_get dt - dtlen 1 ) 42
    // Strict mode: `# *T <owned-binding>` casts
    // hand the caller a raw pointer into a binding the compiler
    // would otherwise auto-drop at scope exit. Even when the pattern
    // is safe in practice, it bypasses the single-owner contract:
    // any later reassignment, sink-pass, explicit free, or scope-
    // exit drop of the source binding invalidates the pointer. Flag
    // it so the user has a chance to either rebind the pointer's
    // referent as a `*T` parameter (carries lifetime by reference)
    // or copy the bytes the pointer points at into a fresh
    // allocation before the source binding's region ends. Only fires
    // under --strict-borrowck and only when gen_expr's last side-
    // channel identifies a SPECIFIC bare-ident source binding —
    // compound expressions (`# *u ( string_data s )`) leave the
    // side-channel unreliable.
    ? & != 0 g_strict_borrowck dst_ptr {
        : s src_id ( nurl_sym_get syms `__last_ident_name__` )
        ? != 0 ( nurl_str_len src_id ) {
            : s src_ty ( nurl_sym_get syms src_id )
            : b src_is_param
            ( str_contains_word ( nurl_sym_get syms `__fn_param_names__` ) src_id )
            // Three independent sources of "would auto-drop":
            //   * src_id appears in the per-binding owned-string /
            //     owned-slice / owned-struct-field side-tables (the
            //     conservative sink-rejection check in gen_call uses
            //     the same shape — strings + struct-fields keyed by
            //     alloca-pointer, slices keyed by name);
            //   * src_id is a NON-parameter heap binding (%Struct /
            //     enum / aggregate), which the conservative
            //     bck_let_alias move-tracker already treats as
            //     auto-drop territory — covers `: String s
            //     ( string_from "..." )` style.
            : s src_ptr ( nurl_sym_get syms ( nurl_str_cat src_id `__ptr` ) )
            : b owned_slc
            ( str_contains_word ( nurl_sym_get syms `__owned_slices__` ) src_id )
            : b owned_str & != 0 ( nurl_str_len src_ptr )
            ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) src_ptr )
            : b owned_sf & != 0 ( nurl_str_len src_ptr )
            ( str_contains_word ( nurl_sym_get syms `__owned_struct_fields__` ) src_ptr )
            : b heap_binding & ! src_is_param ( bck_is_heap_lty src_ty )
            ? | | | owned_str owned_slc owned_sf heap_binding {
                ( bck_esc_warn lex ( nurl_lex_line lex ) ( nurl_str_cat3
                `'# `
                ( nurl_str_cat3 dt ` ` src_id )
                `' casts an owned binding to a raw pointer; the binding is auto-dropped at scope exit and the pointer will outlive it. Take a '*T' parameter or copy the bytes before the binding is dropped` ) )
            } {}
        } {}
    } {}
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
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty st ) )
        ( nurl_print ` ` ) ( nurl_print val )
        ( nurl_print `, ` ) ( nurl_print ( nurl_str_int fld ) ) ( nurl_print `\n` )
        ? ( seq dt elem_ty )
        { ( nurl_set_last_type dt ) ^ ev }
        { ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty elem_ty ) )
            ( nurl_print ` ` ) ( nurl_print ev )
            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty dt ) ) ( nurl_print `\n` )
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
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty st ) )
        ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, 0\n` )
        : i f0iw ( int_width f0t )
        : b f0_is_ptr == ( nurl_str_get f0t - ( nurl_str_len f0t ) 1 ) 42
        : b f0_is_fp | ( seq f0t `double` ) ( seq f0t `float` )
        ? f0_is_fp
        { ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = fptosi ` ) ( nurl_print ( nurl_llty f0t ) )
            ( nurl_print ` ` ) ( nurl_print xv ) ( nurl_print ` to ` )
            ( nurl_print ( nurl_llty dt ) ) ( nurl_print `\n` )
            ( nurl_set_last_type dt ) ^ res }
        {}
        ? & & ! f0_is_fp ! f0_is_ptr == f0iw 0
        { ( die lex ( nurl_str_cat3 `cannot cast '` st `' to an integer: field 0 is an aggregate` ) ) }
        {}
        : s norm ? & ! f0_is_ptr == f0iw 64 xv ( nurl_cg_reg cg )
        ? f0_is_ptr
        { ( nurl_print `  ` ) ( nurl_print norm )
            ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty f0t ) )
            ( nurl_print ` ` ) ( nurl_print xv ) ( nurl_print ` to i64\n` ) }
        { ? != f0iw 64
            { ( nurl_print `  ` ) ( nurl_print norm )
                // The field's own type says how to widen: an unsigned
                // narrow field 0 (`u`/`u16`/`u32`) zero-extends.
                ( nurl_print ? ( ty_is_unsigned f0t ) ` = zext ` ` = sext ` )
                ( nurl_print ( nurl_llty f0t ) )
                ( nurl_print ` ` ) ( nurl_print xv ) ( nurl_print ` to i64\n` ) }
            {} }
        ? == named_dst_iw 64
        { ( nurl_set_last_type dt ) ^ norm }
        { ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = trunc i64 ` ) ( nurl_print norm )
            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty dt ) ) ( nurl_print `\n` )
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
    {  // float ↔ double conversions. The result is a float; `nurl_set_last_type`
        // below resets signedness to signed, so no stale integer-unsigned flag
        // survives into a later int op (the coupling does this automatically).
        ? ( seq st dt )
        { ( nurl_set_last_type dt ) ^ val }
        { ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ? & src_is_float dst_is_double ` = fpext ` ` = fptrunc ` )
            ( nurl_print ( nurl_llty st ) ) ( nurl_print ` ` ) ( nurl_print val )
            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty dt ) ) ( nurl_print `\n` )
            ( nurl_set_last_type dt ) ^ res }
    }
    {}
    ? & src_is_fp ! dst_is_fp
    {  // float-or-double → int: fptoui when the TARGET is unsigned (so a
        // value above the signed max converts correctly instead of becoming
        // poison via fptosi), else fptosi.
        ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ? dst_unsigned ` = fptoui ` ` = fptosi ` )
        ( nurl_print ( nurl_llty st ) ) ( nurl_print ` ` )
        ( nurl_print val ) ( nurl_print ` to ` ) ( nurl_print ( nurl_llty dt ) )
        ( nurl_print `\n` )
        // The integer result's signedness is the cast TARGET's — and dt
        // IS the target type, unsigned spelling included.
        ( nurl_set_last_type dt )
        ^ res
    }
    ? & ! src_is_fp dst_is_fp
    {  // int → float-or-double: uitofp when the SOURCE is unsigned (an
        // unsigned value with the high bit set must NOT be read as a
        // negative number), else sitofp. The source's signedness is in
        // its type (A1) — `u8`..`u64` stay distinct from the i-types.
        ( nurl_print `  ` ) ( nurl_print res )
        ( nurl_print ? ( ty_is_unsigned st ) ` = uitofp ` ` = sitofp ` )
        ( nurl_print ( nurl_llty st ) )
        ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print ` to ` )
        ( nurl_print ( nurl_llty dt ) ) ( nurl_print `\n` )
        // The result is a float — its type carries no integer
        // signedness, so the surrounding `# i64 # f …` round-trip's
        // later multiply/divide can't inherit a stale unsigned marker.
        ( nurl_set_last_type dt )
        ^ res
    }
    { ? & src_ptr == ( int_width dt ) 64
        {  // pointer → 64-bit int (i64 or u64): ptrtoint
            ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty st ) )
            ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print ` to i64\n` )
            ( nurl_set_last_type dt )
            ^ res
        }
        { ? & dst_ptr == ( int_width st ) 64
            {  // i64 → pointer: inttoptr
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = inttoptr i64 ` ) ( nurl_print val )
                ( nurl_print ` to ` ) ( nurl_print ( nurl_llty dt ) ) ( nurl_print `\n` )
                ( nurl_set_last_type dt )
                ^ res
            }
            { ? & src_ptr dst_ptr
                {  // pointer → pointer: bitcast
                    ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = bitcast ` ) ( nurl_print ( nurl_llty st ) )
                    ( nurl_print ` ` ) ( nurl_print val )
                    ( nurl_print ` to ` ) ( nurl_print ( nurl_llty dt ) ) ( nurl_print `\n` )
                    ( nurl_set_last_type dt )
                    ^ res
                }
                { ? & == ( int_width st ) 64 == ( nurl_str_get dt 0 ) 37
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
                        //       Closes a vec_get codegen bug on
                        //       multi-field T no longer miscompiles.
                        : s sname ( nurl_str_slice dt 1 - dtlen 1 )
                        : s f0_ty ( nurl_sym_get syms ( nurl_str_cat3 sname `__idx_0` `__type` ) )
                        : b f0_is_ptr & != 0 ( nurl_str_len f0_ty )
                        == ( nurl_str_get f0_ty - ( nurl_str_len f0_ty ) 1 ) 42
                        : b f0_is_i64 == ( int_width f0_ty ) 64
                        // Empty f0_ty: struct not fully registered — fall
                        // through to legacy insertvalue (preserves prior
                        // behaviour for anon / partially-known types).
                        : b f0_unknown == 0 ( nurl_str_len f0_ty )
                        ? f0_is_ptr
                        { : s pv ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print pv )
                            ( nurl_print ` = inttoptr i64 ` ) ( nurl_print val )
                            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty f0_ty ) ) ( nurl_print `\n` )
                            ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty dt ) )
                            ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty f0_ty ) )
                            ( nurl_print ` ` ) ( nurl_print pv ) ( nurl_print `, 0\n` )
                            ( nurl_set_last_type dt )
                            ^ res }
                        { ? | f0_is_i64 f0_unknown
                            { ( nurl_print `  ` ) ( nurl_print res )
                                ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty dt ) )
                                ( nurl_print ` undef, i64 ` ) ( nurl_print val ) ( nurl_print `, 0\n` )
                                ( nurl_set_last_type dt )
                                ^ res }
                            {  // f0 is neither pointer, i64, nor unknown —
                                // produce a zero-initialised whole struct.
                                ( nurl_set_last_type dt )
                                ^ `zeroinitializer` }
                        }
                    }
                    {  // Integer → anonymous aggregate (`{ … }` option /
                        // slice / result, or `[ … ]`): the only meaningful
                        // such cast is the `# A 0` dummy-payload idiom where
                        // the element type A is itself an aggregate (e.g.
                        // `vec_get [?String]` → `@ ?A { F # A 0 }`). LLVM
                        // forbids an integer constant at aggregate type, so
                        // produce a zero-initialised aggregate.
                        ? & > ( int_width st ) 0 | == ( nurl_str_get dt 0 ) 123 == ( nurl_str_get dt 0 ) 91
                        { ( nurl_set_last_type dt ) ^ `zeroinitializer` }
                        {}
                        // Integer-width conversion (iN → iM).  Sub-cases:
                        //   * Narrow (sw > dw): trunc.
                        //   * Widen, source is i1 (a boolean from a
                        //     comparison / `&` / `|` / `!`): zext ALWAYS.
                        //     NURL has no signed 1-bit type, so boolean
                        //     true is canonically 1 — `sext i1 1` would
                        //     yield -1 and silently break every `# i
                        //     <bool>` (is_digit / is_alpha returned -1).
                        //   * Widen, source unsigned (st is `u8`..`u32` —
                        //     signedness is IN the type since A1): zext.
                        //   * Widen, source signed (default): sext.
                        // Equal widths or non-integer types: no-op — the
                        // result takes the TARGET's type (unsigned
                        // spelling included), so `# u <i8>` reinterprets
                        // and an enclosing op reads u8 off the type.
                        : i sw ( int_width st )
                        : i dw ( int_width dt )
                        ? & & > sw 0 > dw 0 != sw dw
                        { : b src_is_bool ( seq st `i1` )
                            : s widen_inst ? | src_is_bool ( ty_is_unsigned st ) ` = zext ` ` = sext `
                            ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ? > dw sw widen_inst ` = trunc ` )
                            ( nurl_print ( nurl_llty st ) ) ( nurl_print ` ` ) ( nurl_print val )
                            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty dt ) ) ( nurl_print `\n` )
                            ( nurl_set_last_type dt )
                            ^ res
                        }
                        { ( nurl_set_last_type dt )
                            ^ val }
                    }
                }
            }
        }
    }
}

// ── Member . obj field|index ───────────────────────────────────────

@ gen_member i lex i syms i cg → s {
    ( nurl_lex_advance lex )
    : s ov ( gen_operand lex syms cg )
    : s ot ( nurl_get_last_type )
    // For raw-pointer loads `*X p`, the element's signedness is in the
    // pointer type itself (A1): `*u` is `u8*`, so stripping the `*`
    // yields `u8` and downstream `# i …` casts pick zext off the type —
    // no snapshot/restore dance. (Formerly a high-bit-set byte (`0x89`)
    // sign-extended to `0xFFFFFFFFFFFFFF89` when the flag went stale.)

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
            ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_type ) )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty ot ) )
            ( nurl_print ` ` ) ( nurl_print ov )
            ( nurl_print `, i32 ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
            ( nurl_print `  ` ) ( nurl_print res )
            ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty elem_type ) )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem_type ) )
            ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
            ( nurl_set_last_type elem_type )
            ^ res
        }
        { : s elem_type ( nurl_str_slice ot 0 - otlen 1 )
            : b elem_is_struct == ( nurl_str_get elem_type 0 ) 37
            // Struct pointer (%T*): if the IDENT names a struct field,
            // emit `gep %T, %T* ov, i32 0, i32 fidx` + load. A struct field
            // ALWAYS wins over a same-named in-scope variable — you cannot
            // array-index a struct pointer by a field name, and field access
            // is the intent. (Previously a field whose name matched an int
            // variable/param in scope was mis-routed to the variable-index
            // path below → a silent miscompile, e.g. `. m state` with an `i
            // state` parameter loaded the param as an array index instead of
            // reading the field.) The variable-index fallback is reached only
            // when the IDENT is NOT a field: raw pointers, or array-of-struct
            // indexed by a (non-field-named) variable.
            : ~ b is_field_access F
            : s fname ( nurl_lex_val lex )
            : ~ s fidx_s ``
            : ~ s ftype ``
            ? & elem_is_struct ( is_ident_tok ( nurl_lex_type lex ) )
            { : s sname ( nurl_str_slice elem_type 1 - ( nurl_str_len elem_type ) 1 )
                // A tparam-substituted element type has no source-accessible
                // fields (it was an opaque type variable in the generic) →
                // suppress the field lookup so `. data idx` indexes the array.
                : s fidx_check ? ( str_contains_word g_mono_tparam_tys sname ) `` ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__idx` ) ) ) )
                ? != 0 ( nurl_str_len fidx_check )
                { = is_field_access T
                    = fidx_s fidx_check
                    = ftype ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
                }
                {}
            }
            {}
            ? is_field_access
            { ( nurl_lex_advance lex )  // consume field name
                : i fidx ( nurl_str_to_int fidx_s )
                : s gep ( nurl_cg_reg cg )
                : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print gep )
                ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_type ) )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty ot ) )
                ( nurl_print ` ` ) ( nurl_print ov )
                ( nurl_print `, i32 0, i32 ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty ftype ) )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty ftype ) )
                ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                // ftype is the field's raw declared type — an unsigned
                // field's signedness reaches an enclosing widening cast
                // through the type itself.
                ( nurl_set_last_type ftype )
                ^ res
            }
            {  // Variable / arbitrary expression index → array-style access
                : s idx_val ( gen_expr lex syms cg )
                : s idx_type ( nurl_get_last_type )
                : s gep ( nurl_cg_reg cg )
                : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print gep )
                ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_type ) )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty ot ) )
                ( nurl_print ` ` ) ( nurl_print ov )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty idx_type ) ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty elem_type ) )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem_type ) )
                ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
                ( nurl_set_last_type elem_type )
                ^ res
            }
        }
    }
    {  // Non-pointer type: handle struct field access or aggregate indexing.
        // A field / element access requires an aggregate: a named struct/enum
        // (`%T`), or an opt / res / slice / closure record (`{ … }`). A scalar
        // primitive (i64 / double / i1 / i8 / …) has no fields — `. n x` or
        // `. n 0` on an `i` binding used to emit `extractvalue i64 …`, IR that
        // nurlc accepted (rc 0) and only clang / llvm-as rejected ("extractvalue
        // operand must be aggregate type"). Reject it at the source.
        ? != 0 ( nurl_str_len ot )
        { ? & != ( nurl_str_get ot 0 ) 123 != ( nurl_str_get ot 0 ) 37
            { ( die lex ( nurl_str_cat3 `cannot access a field or element of '` ( llvm_to_nurl ot ) `' — it is not a struct, enum, slice, or pointer` ) ) }
            {} }
        {}
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
            {  // Extractvalue for specific field (idx > 0) or primitive types.
                // Range-check first: `. agg N` with N past the last field used
                // to emit `extractvalue … , N` that only clang/llvm-as rejected
                // ("invalid indices for extractvalue").
                : i fcount ( agg_field_count syms ot )
                ? & >= fcount 0 >= idx fcount
                { ( die lex ( nurl_str_cat
                    ( nurl_str_cat3 `index ` ( nurl_str_int idx ) ` is out of range for type '` )
                    ( nurl_str_cat ( llvm_to_nurl ot )
                    ( nurl_str_cat3 `' — it has ` ( nurl_str_int fcount ) ` field(s)` ) ) ) ) }
                {}
                : s ft ( compound_field_type ot idx )
                : s res ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print res )
                ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty ot ) )
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
                // Lint: a slice variable-index access `. slice i` loads the
                // index binding directly below (not via gen_ident), so mark
                // it read here. Harmless for struct field names / ptr/length.
                ( lint_note_read fname )
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
                        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty ot ) )
                        ( nurl_print ` ` ) ( nurl_print ov ) ( nurl_print `, 0\n` )
                        ( nurl_set_last_type ptr_ty )
                        ^ res
                    }
                    { ? ( seq fname `length` )
                        {  // length: extractvalue 1, type = i64
                            : s res ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty ot ) )
                            ( nurl_print ` ` ) ( nurl_print ov ) ( nurl_print `, 1\n` )
                            ( nurl_set_last_type `i64` )
                            ^ res
                        }
                        {  // Variable element index: extract data ptr, GEP, load
                            : s ptr_ty ( nurl_str_slice ot 2 - - ( nurl_str_len ot ) 7 2 )
                            : s elem_ty ( nurl_str_slice ptr_ty 0 - ( nurl_str_len ptr_ty ) 1 )
                            // Resolve the index binding (fname) to a value the
                            // same way gen_ident does: a local / match-payload /
                            // loop / inout / capture binding carries a `__ptr`
                            // (load it); a const or enum variant carries
                            // `__global` (load `@name`); a by-value function
                            // PARAMETER carries neither and resolves directly to
                            // its SSA register `%name`. The previous code assumed
                            // `<name>__ptr` always existed and, for a parameter
                            // index, emitted `load i64, i64* ` with an EMPTY
                            // pointer operand — invalid IR that nurlc accepted
                            // (rc 0, no diagnostic) and only clang rejected.
                            : s idx_lt0 ( nurl_sym_get syms fname )
                            : s idx_lt ? == 0 ( nurl_str_len idx_lt0 ) `i64` idx_lt0
                            : s idx_ptr ( nurl_sym_get syms ( nurl_str_cat fname `__ptr` ) )
                            : s idx_glb ( nurl_sym_get syms ( nurl_str_cat fname `__global` ) )
                            : s idx_val ? != 0 ( nurl_str_len idx_ptr )
                            ( load_var cg idx_lt idx_ptr )
                            ? != 0 ( nurl_str_len idx_glb )
                            ( load_var cg idx_lt ( nurl_str_cat `@` fname ) )
                            ( nurl_str_cat `%` fname )
                            // Extract data pointer from slice aggregate
                            : s data_ptr ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print data_ptr )
                            ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty ot ) )
                            ( nurl_print ` ` ) ( nurl_print ov ) ( nurl_print `, 0\n` )
                            // GEP + load element
                            : s gep ( nurl_cg_reg cg )
                            : s res ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print gep )
                            ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_ty ) )
                            ( nurl_print `, ` ) ( nurl_print ( nurl_llty ptr_ty ) )
                            ( nurl_print ` ` ) ( nurl_print data_ptr )
                            ( nurl_print `, ` ) ( nurl_print ( nurl_llty idx_lt ) ) ( nurl_print ` ` ) ( nurl_print idx_val ) ( nurl_print `\n` )
                            ( nurl_print `  ` ) ( nurl_print res )
                            ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty elem_ty ) )
                            ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem_ty ) )
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
                    // No such field: the lookup is empty, and the old code fed
                    // `nurl_str_to_int ""` = 0 into `extractvalue %T v, 0` —
                    // silently reading the WRONG field (a miscompile), or
                    // emitting a malformed index. Reject the typo at the source.
                    ? == 0 ( nurl_str_len fidx_s )
                    { ( die lex ( nurl_str_cat3 `type '` ( llvm_to_nurl ot )
                        ( nurl_str_cat3 `' has no field '` fname `'` ) ) ) }
                    {}
                    : s ftype ( nurl_sym_get syms ( nurl_str_cat sname ( nurl_str_cat `__` ( nurl_str_cat fname `__type` ) ) ) )
                    : i fidx ( nurl_str_to_int fidx_s )
                    : s res ( nurl_cg_reg cg )
                    ( nurl_print `  ` ) ( nurl_print res )
                    ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty ot ) )
                    ( nurl_print ` ` ) ( nurl_print ov )
                    ( nurl_print `, ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
                    // ftype is the field's raw declared type — an
                    // enclosing widening cast reads zext-vs-sext off it.
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
    // zeroinitializer (not undef) so fields the literal leaves out are
    // all-zero. Matters for payload-less None — `@ ?T { F }` — where the
    // payload slot must read as a NULL handle (the runtime and stdlib
    // treat NULL as an explicit safe no-op everywhere: nurl_peek,
    // string_free, vec_free…), never as undef garbage that trips
    // UBSan/ASan when a defensive read touches it.
    : ~ s result `zeroinitializer`
    : ~ i idx 0
    // Result construction (`{ i1, T, E }`): a result literal is a 3-field
    // `{ i1, ... }` aggregate. Its two source values are the tag (idx 0) and a
    // single payload (idx 1) which routes BY VALUE to field 1 (Ok) or field 2
    // (Err) per the tag — never the i64-squeeze the legacy `{ i1, i64 }` layout
    // forced. `res_is_ok` is captured from the tag literal at idx 0.
    : b agg_is_res & & >= ( nurl_str_len agg_ty ) 6
    ( seq ( nurl_str_slice agg_ty 0 6 ) `{ i1, ` )
    == ( agg_field_count syms agg_ty ) 3
    : ~ b res_is_ok F
    // Phase 2C/2D: collect indices of fields populated by a fresh allocating
    // call (i8* via nurl_str_cat et al, or slice via `[T | ...]` literal /
    // slice-returning call), AND nested owned subfields from inner struct
    // aggregate literals. Exposed via `__last_agg_owned_fields__` as
    // space-separated tokens `<path>:<kind>:<leaf_sname>:<leaf_idx>` — path
    // is dot-separated (flat: single int; nested: e.g. `0.1`). Only applies
    // to named-struct aggregates (agg_ty starting with %).
    : ~ s owned_field_idxs ``
    // Current struct's bare name (without leading %). Empty for anon aggs.
    : ~ s cur_sname ``
    ? == ( nurl_str_get agg_ty 0 ) 37
    { = cur_sname ( nurl_str_slice agg_ty 1 - ( nurl_str_len agg_ty ) 1 ) }
    {}
    // Enum-literal payload-arity check (critic A7, ghost-variant half):
    // when this literal constructs a DECLARED enum, snapshot the leading
    // variant ident + its `__paycount` now; after the field loop, more
    // supplied values than the variant declares is a hard error (the
    // overflow value would land in a slot the variant doesn't own —
    // invalid IR or a silently misread sibling slot). Underflow stays
    // legal: zeroinitializer backs the payload-less `@ ?T { F }` idiom.
    : ~ i enum_paycount -1
    : ~ s enum_vname ``
    ? & != 0 ( nurl_str_len cur_sname )
    != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat cur_sname `__variants` ) ) )
    { ? ( is_ident_tok ( nurl_lex_type lex ) )
        { : s __ev ( nurl_lex_val lex )
            : s __ev_pc ( nurl_sym_get syms ( nurl_str_cat __ev `__paycount` ) )
            ? != 0 ( nurl_str_len __ev_pc )
            { = enum_vname __ev
                = enum_paycount ( nurl_str_to_int __ev_pc ) }
            {}
        }
        {}
    }
    {}
    // Closure-escape (docs/MEMORY.md §2.3):
    // track the deepest referent depth among the field values. A field
    // that is a stack reference (a closure capturing a binding by
    // pointer, or a binding / aggregate transitively holding one)
    // makes the WHOLE aggregate a stack reference of that depth, so
    // `gen_let_or_struct` / `gen_ret` reject the escape — otherwise
    // wrapping a byref closure in a struct would silently defeat the
    // `^`-return + escape-call checks.
    : ~ i agg_refdepth 0
    // Return-escape (docs/MEMORY.md §2.8): names of the enclosing
    // function's parameters embedded as a field of THIS aggregate. A
    // parameter is not a stack reference inside its own function (its
    // refdepth is 0), so agg_refdepth alone can't see that returning
    // `@ Slot { cb }` hands `cb` back out. gen_ret reads this list to
    // record those parameters as returned, so a caller passing a stack
    // reference there is flagged just like `^ cb`.
    : ~ s agg_param_idents ``
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
        // §2.8: snapshot whether this field is a bare identifier, to tell
        // a direct parameter embed (`{ cb }`) from a derived value.
        : i fld_first_tt ( nurl_lex_type lex )
        : s fld_first_val ( nurl_lex_val lex )
        // Result tag (idx 0): `T` ⇒ Ok (payload→field 1), `F` ⇒ Err (→field 2).
        ? & agg_is_res == idx 0 { = res_is_ok ( seq fld_first_val `T` ) } {}
        : s fval ( gen_expr lex syms cg )
        : s fty ( nurl_get_last_type )
        // Struct-literal field checks. PLAIN structs only — enum / option /
        // result variant literals reach here too but use the enum_paycount
        // path (overflow) + zeroinitializer for omitted payload slots, so
        // they are excluded (enum_paycount set OR a `__variants` registry).
        ? & & != 0 ( nurl_str_len cur_sname ) == enum_paycount -1
        == 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat cur_sname `__variants` ) ) )
        { : s __slfc ( nurl_sym_get syms ( nurl_str_cat cur_sname `__field_count` ) )
            ? != 0 ( nurl_str_len __slfc )
            {  // (a) more values than the struct has fields — the surplus
                // would insertvalue into a non-existent slot (invalid IR).
                ? >= idx ( nurl_str_to_int __slfc )
                { ( die lex ( nurl_str_cat
                    ( nurl_str_cat4 `struct literal '` cur_sname `' has more field values than its ` __slfc )
                    ` field(s) — the extra value has no slot` ) ) }
                {}
                // (b) never-legal field-type clash: float-vs-non-float, or a
                // different named struct by value. Int width / signedness /
                // pointer-stash coercions stay legal and are NOT flagged.
                : s __sldft ( nurl_sym_get syms ( nurl_str_cat3 cur_sname `__idx_` ( nurl_str_cat ( nurl_str_int idx ) `__type` ) ) )
                ? != 0 ( nurl_str_len __sldft )
                { : b __slvf | ( seq fty `double` ) ( seq fty `float` )
                    : b __sldf | ( seq __sldft `double` ) ( seq __sldft `float` )
                    ? | != __slvf __sldf ( __arg_named_struct_mismatch fty __sldft )
                    { ( die lex ( nurl_str_cat3
                        ( nurl_str_cat4 `field ` ( nurl_str_int idx ) ` of struct literal '` cur_sname )
                        ( nurl_str_cat4 `' expects type '` __sldft `' but the value has type '` fty )
                        `' — NURL has no implicit conversions` ) ) }
                    {}
                }
                {}
            }
            {}
        }
        {}
        // §2.8: record a field that is exactly a bare parameter of the
        // enclosing function, so `^ @ T { … param … }` propagates that
        // parameter's reference out through the returned aggregate.
        ? & & != g_borrowck 0 ( is_ident_tok fld_first_tt )
        & ( seq ( nurl_sym_get syms `__last_ident_name__` ) fld_first_val )
        ( str_contains_word ( nurl_sym_get syms `__fn_param_names__` ) fld_first_val )
        { = agg_param_idents ? == 0 ( nurl_str_len agg_param_idents )
            fld_first_val
            ( nurl_str_cat3 agg_param_idents ` ` fld_first_val ) }
        {}
        // The value's signedness for the int-width coercions below (zext
        // vs sext when widening into a wider payload/field slot) rides
        // the value's own type `fty` — `u8`..`u64` spellings are
        // distinct since A1.
        : b fld_unsigned ( ty_is_unsigned fty )
        // Field is a stack reference if gen_closure_expr / a nested
        // gen_agg_lit just advertised one, or the field named a binding
        // tagged `<name>__refdepth`. Carry up the deepest such depth.
        : i fld_refdepth ( bck_expr_refdepth syms
        ( nurl_sym_get syms `__last_ident_name__` ) )
        ? > fld_refdepth agg_refdepth { = agg_refdepth fld_refdepth } {}
        : s ret_owned ( nurl_sym_get syms `__last_call_ret_owned__` )
        : b is_str_fresh & ( seq ( nurl_llty fty ) `i8*` ) ( seq ret_owned `str` )
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
        { : ~ s sub ( nurl_sym_get syms `__last_agg_owned_fields__` )
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
        : ~ s actual_fval fval
        : ~ s actual_fty fty
        // The insertvalue index: normally the literal position, but a result
        // payload (idx 1) routes to field 1 (Ok) or field 2 (Err) by tag.
        : ~ i ins_idx idx
        // Result payload (`{ i1, T, E }`, idx 1): store BY VALUE into the Ok/Err
        // slot, coercing only width/i1/enum-wrap via coerce_store_val. The other
        // slot stays zeroinitialized. A void Ok slot (`!v E`) is an i1 placeholder
        // the Ok arm never reads, so the (harmless) literal value is dropped in.
        ? & agg_is_res == idx 1
        { : i res_tgt ? res_is_ok 1 2
            : s res_tgt_ty ( compound_field_type agg_ty res_tgt )
            = actual_fval ( coerce_store_val lex fval fty res_tgt_ty syms cg )
            = actual_fty res_tgt_ty
            = ins_idx res_tgt }
        {}
        ? & > idx 0 ! agg_is_res
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
                { ? | ( seq fty `sref` ) == ( nurl_str_get fty - ( nurl_str_len fty ) 1 ) 42
                    {  // Any raw pointer (`i8*`, or a NURL `*Struct` → `%Struct*`)
                        // — store it directly in the i64 payload slot via
                        // ptrtoint. A `%Struct*` pointer ends in `*` and must
                        // NOT fall through to the `%`-named struct branch below
                        // (which would heap-box it as if it were a by-value
                        // struct handle). The `?? T p` arm recovers it with a
                        // single inttoptr.
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print ` ` )
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
                            // Inline-f0 is correct ONLY for a SINGLE-field
                            // pointer-handle struct (Vec/String/Response). A
                            // multi-field struct whose f0 happens to be a
                            // pointer (e.g. TcpListener { s raw i is_tls … })
                            // must be heap-boxed, or fields 1.. are dropped.
                            : s fc_a ( nurl_sym_get syms ( nurl_str_cat sname2 `__field_count` ) )
                            : b single_a & != 0 ( nurl_str_len fc_a ) == ( nurl_str_to_int fc_a ) 1
                            : b f0_is_ptr & != 0 ( nurl_str_len f0_ty )
                            == ( nurl_str_get f0_ty - ( nurl_str_len f0_ty ) 1 ) 42
                            ? & single_a f0_is_ptr
                            {  // Single-pointer-handle struct (Vec, String,
                                // Response, ...): extract f0 + ptrtoint into
                                // the i64 payload slot.
                                : s xv ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print xv )
                                ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print ` ` ) ( nurl_print fval ) ( nurl_print `, 0\n` )
                                : s pi ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print pi )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty f0_ty ) )
                                ( nurl_print ` ` ) ( nurl_print xv ) ( nurl_print ` to i64\n` )
                                = actual_fval pi }
                            {  // Multi-field / non-pointer-f0 struct: heap-box
                                // the whole struct (alloc, store, ptrtoint)
                                // and stuff the pointer into the i64 slot.
                                // The receiving ?? match arm unboxes via the
                                // wide-struct branch in gen_match.
                                : s sz_reg ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print sz_reg )
                                ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `, ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `* null, i32 1\n` )
                                : s sz_int ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print sz_int )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `* ` ) ( nurl_print sz_reg ) ( nurl_print ` to i64\n` )
                                : s box_raw ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_raw )
                                ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print sz_int ) ( nurl_print `)` ) ( emit_dbg_eol )
                                : s box_ptr ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_ptr )
                                ( nurl_print ` = bitcast i8* ` ) ( nurl_print box_raw )
                                ( nurl_print ` to ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print `*\n` )
                                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print ` ` ) ( nurl_print fval )
                                ( nurl_print `, ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print `\n` )
                                : s box_i ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_i )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) )
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
                                ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `, ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `* null, i32 1\n` )
                                : s sz_int ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print sz_int )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `* ` ) ( nurl_print sz_reg ) ( nurl_print ` to i64\n` )
                                : s box_raw ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_raw )
                                ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print sz_int ) ( nurl_print `)` ) ( emit_dbg_eol )
                                : s box_ptr ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_ptr )
                                ( nurl_print ` = bitcast i8* ` ) ( nurl_print box_raw )
                                ( nurl_print ` to ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print `*\n` )
                                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print ` ` ) ( nurl_print fval )
                                ( nurl_print `, ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print `\n` )
                                : s box_i ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print box_i )
                                ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) )
                                ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print ` to i64\n` )
                                = actual_fval box_i
                            } {
                                // Narrow tag-only enum: extract i64 tag.
                                : s xv ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print xv )
                                ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty fty ) )
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
                    {  // Integer payload whose width differs from the value's.
                        // For `! T E` the payload slot is always i64, so an
                        // i64 value lands here and uses itself as-is. But an
                        // OPTION `? T` payload field carries T's REAL width
                        // (`? u` → i8, `? u16` → i16, `? i32` → i32), so an
                        // i64 literal / value must be narrowed — without this
                        // `@ ?u { T 0x86 }` emitted `insertvalue { i1, i8 }
                        // …, i64 134, 1` and clang rejected the type mismatch.
                        // trunc when the value is wider; sext/zext (per the
                        // value's unsigned flag) when narrower than the field.
                        : i __pw ( int_width payload_ty )
                        : i __vw ( int_width fty )
                        ? & & > __pw 0 > __vw 0 != __pw __vw
                        { : s __cv ( nurl_cg_reg cg )
                            : s __op ? > __vw __pw `trunc`
                            ? fld_unsigned `zext` `sext`
                            ( nurl_print `  ` ) ( nurl_print __cv )
                            ( nurl_print ` = ` ) ( nurl_print __op )
                            ( nurl_print ` ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print ` ` )
                            ( nurl_print fval ) ( nurl_print ` to ` ) ( nurl_print ( nurl_llty payload_ty ) )
                            ( nurl_print `\n` )
                            = actual_fval __cv
                            = actual_fty payload_ty }
                        {  // payload_ty is not an int. The one remaining
                            // shape is an OPTION whose payload is a named
                            // enum (`? E`, payload field `%E`) carrying a
                            // bare no-payload variant — which evaluates to
                            // its i64 tag here. The option slot wants the
                            // whole `%E` aggregate, so wrap the tag with
                            // `insertvalue %E zeroinitializer, i64 tag, 0`
                            // (the inverse of the `! T E` tag-extract above;
                            // a no-payload variant leaves every other enum
                            // field zero). Without this `@ ?E { T A }`
                            // emitted `insertvalue { i1, %E } …, i64 …, 1`
                            // and clang rejected the type mismatch.
                            ? & == ( nurl_str_get payload_ty 0 ) 37 == ( int_width fty ) 64
                            { : s __en ( nurl_str_slice payload_ty 1 - ( nurl_str_len payload_ty ) 1 )
                                : s __ev ( nurl_sym_get syms ( nurl_str_cat __en `__variants` ) )
                                ? != 0 ( nurl_str_len __ev )
                                { : s __wrap ( nurl_cg_reg cg )
                                    ( nurl_print `  ` ) ( nurl_print __wrap )
                                    ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty payload_ty ) )
                                    ( nurl_print ` zeroinitializer, i64 ` ) ( nurl_print fval )
                                    ( nurl_print `, 0\n` )
                                    = actual_fval __wrap
                                    = actual_fty payload_ty }
                                {} }
                            {}
                        }
                    }
                }
            }
            {  // Check if this is actually an enum type
                // Extract type name from agg_ty (e.g., "%Slice" from "%Slice")
                : ~ s type_name ``
                ? == ( nurl_str_get agg_ty 0 ) 37
                {  // Named type starting with '%' - extract name
                    : ~ i end_pos 1
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
                {  // enum payload: convert values to the uniform i64 slot
                    ? ( seq fty `i1` )
                    {  // Convert boolean to i64
                        : s conv_reg1 ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg1 )
                        ( nurl_print ` = zext i1 ` ) ( nurl_print fval ) ( nurl_print ` to i64\n` )
                        = actual_fval conv_reg1
                        = actual_fty `i64`
                    }
                    ? ( is_float_ty fty )
                    {  // Float payload → i64 slot. Bitcast the float to a
                        // same-width int (f32 widens i32→i64).
                        // The match arm inverts this (emit_enum_float_extract).
                        //
                        // Pick the slot width from the variant's DECLARED payload
                        // type, NOT the value's: a float LITERAL is always
                        // `double`, so an `f32` payload (`@ N { F32 2.25 }`) would
                        // otherwise bitcast the whole double to i64, while
                        // emit_enum_float_extract reads the low 32 bits back as a
                        // float → garbage (returned 0). The payload index is
                        // idx-1 (idx 0 is the tag slot).
                        : s decl_pt ? & != 0 ( nurl_str_len enum_vname ) >= idx 1
                        ( nurl_sym_get syms ( nurl_str_cat3 enum_vname `__payload__` ( nurl_str_int - idx 1 ) ) )
                        fty
                        : ~ s ibits ``
                        ? ( seq decl_pt `float` )
                        {  // f32 slot: ensure the value is `float` (fptrunc a
                            // double literal), then bitcast→i32, zext→i64.
                            : ~ s fv32 fval
                            ? ( seq fty `double` )
                            { : s ftr ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print ftr )
                                ( nurl_print ` = fptrunc double ` ) ( nurl_print fval )
                                ( nurl_print ` to float\n` )
                                = fv32 ftr }
                            {}
                            : s b32 ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print b32 )
                            ( nurl_print ` = bitcast float ` ) ( nurl_print fv32 ) ( nurl_print ` to i32\n` )
                            = ibits ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print ibits )
                            ( nurl_print ` = zext i32 ` ) ( nurl_print b32 ) ( nurl_print ` to i64\n` ) }
                        {  // double slot: ensure the value is `double` (fpext an
                            // f32 value), then bitcast→i64.
                            : ~ s fv64 fval
                            ? ( seq fty `float` )
                            { : s fpe ( nurl_cg_reg cg )
                                ( nurl_print `  ` ) ( nurl_print fpe )
                                ( nurl_print ` = fpext float ` ) ( nurl_print fval )
                                ( nurl_print ` to double\n` )
                                = fv64 fpe }
                            {}
                            = ibits ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print ibits )
                            ( nurl_print ` = bitcast double ` ) ( nurl_print fv64 ) ( nurl_print ` to i64\n` ) }
                        = actual_fval ibits
                        = actual_fty `i64`
                    }
                    ? & > ( int_width fty ) 0 ! ( seq fty `i1` )
                    {  // Integer payload → i64 slot. A NARROW int (i8/i16/i32,
                        // incl. the unsigned u/u16/u32) widens to i64 — zext
                        // when the payload value is unsigned (`fld_unsigned`),
                        // sext otherwise. i64 payloads ride the slot as-is.
                        : ~ s wide_val fval
                        ? < ( int_width fty ) 64
                        { : s ext_reg ( nurl_cg_reg cg )
                            : s ext_op ? fld_unsigned ` = zext ` ` = sext `
                            ( nurl_print `  ` ) ( nurl_print ext_reg ) ( nurl_print ext_op )
                            ( nurl_print ( nurl_llty fty ) ) ( nurl_print ` ` ) ( nurl_print fval ) ( nurl_print ` to i64\n` )
                            = wide_val ext_reg }
                        {}
                        = actual_fval wide_val
                        = actual_fty `i64`
                    }
                    ? | ( seq fty `sref` ) ( seq ( nurl_llty fty ) `i8*` )
                    {  // String pointer → i64 slot via ptrtoint
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print ` ` )
                        ( nurl_print fval ) ( nurl_print ` to i64\n` )
                        = actual_fval conv_reg
                        = actual_fty `i64`
                    }
                    ? == ( nurl_str_get fty 0 ) 123
                    {  // Anonymous aggregate (e.g., { i1, i64 }): alloca + store +
                        // ptrtoint into the i64 slot
                        : s alloc_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print alloc_reg )
                        ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print `\n` )
                        ( nurl_print `  store ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print ` ` )
                        ( nurl_print fval ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty fty ) )
                        ( nurl_print `* ` ) ( nurl_print alloc_reg ) ( nurl_print `\n` )
                        : s conv_reg ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print conv_reg )
                        ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print `* ` )
                        ( nurl_print alloc_reg ) ( nurl_print ` to i64\n` )
                        = actual_fval conv_reg
                        = actual_fty `i64`
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
                            ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty fty ) )
                            ( nurl_print ` ` ) ( nurl_print fval ) ( nurl_print `, 0\n` )
                            : s pcast ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print pcast )
                            ( nurl_print ` = ptrtoint ` ) ( nurl_print f0_ty3 )
                            ( nurl_print ` ` ) ( nurl_print xv3 ) ( nurl_print ` to i64\n` )
                            = actual_fval pcast
                            = actual_fty `i64` }
                        { : s sz_reg ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print sz_reg )
                            ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty fty ) )
                            ( nurl_print `, ` ) ( nurl_print ( nurl_llty fty ) )
                            ( nurl_print `* null, i32 1\n` )
                            : s sz_int ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print sz_int )
                            ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) )
                            ( nurl_print `* ` ) ( nurl_print sz_reg ) ( nurl_print ` to i64\n` )
                            : s box_raw ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print box_raw )
                            ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print sz_int ) ( nurl_print `)` ) ( emit_dbg_eol )
                            : s box_ptr ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print box_ptr )
                            ( nurl_print ` = bitcast i8* ` ) ( nurl_print box_raw )
                            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print `*\n` )
                            ( nurl_print `  store ` ) ( nurl_print ( nurl_llty fty ) )
                            ( nurl_print ` ` ) ( nurl_print fval )
                            ( nurl_print `, ` ) ( nurl_print ( nurl_llty fty ) )
                            ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print `\n` )
                            : s box_cast ( nurl_cg_reg cg )
                            ( nurl_print `  ` ) ( nurl_print box_cast )
                            ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) )
                            ( nurl_print `* ` ) ( nurl_print box_ptr ) ( nurl_print ` to i64\n` )
                            = actual_fval box_cast
                            = actual_fty `i64` }
                    }
                    ? | ( seq fty `ptr` ) == ( nurl_str_get fty - ( nurl_str_len fty ) 1 ) 42
                    {  // Pointer payload (`%Ast*`, or an opaque `ptr` value):
                        // ptrtoint into the i64 slot. Before the i64-slot
                        // change these rode the ptr slot untouched; the match
                        // arm recovers them with one inttoptr.
                        : s pconv ( nurl_cg_reg cg )
                        ( nurl_print `  ` ) ( nurl_print pconv )
                        ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty fty ) ) ( nurl_print ` ` )
                        ( nurl_print fval ) ( nurl_print ` to i64\n` )
                        = actual_fval pconv
                        = actual_fty `i64`
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
            // Widen with zext when the VALUE is unsigned (`fld_unsigned`,
            // read off the value's own type) — storing a `u` byte 130
            // into an i64 field must give 130, not −126. sext only for a
            // signed source; trunc when the field is narrower.
            : s widen_op ? fld_unsigned ` = zext ` ` = sext `
            : s coerce_op ? > decl_iw have_iw widen_op ` = trunc `
            ( nurl_print `  ` ) ( nurl_print cv )
            ( nurl_print coerce_op )
            ( nurl_print ( nurl_llty actual_fty ) ) ( nurl_print ` ` ) ( nurl_print actual_fval )
            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty decl_fty ) ) ( nurl_print `\n` )
            = actual_fval cv
            = actual_fty decl_fty }
        {}
        // Float-width coercion (mirrors the int-width block). A float LITERAL is
        // always emitted as `double`, so placing one in an `f32` (LLVM `float`)
        // field needs `fptrunc`; an `f32` value in an `f` field needs `fpext`.
        // Without this `@ Vec3 { 1.5 2.5 3.5 }` inserted a `double` into a
        // `float` field — IR nurlc accepted but clang rejected ("insertvalue
        // operand and field disagree in type: 'double' instead of 'float'").
        // Enum / opt-res payloads have no `__idx_N__type` roster (decl_fty
        // empty) and ran their own coercion above, so they are unaffected.
        ? & ( seq decl_fty `float` ) ( seq actual_fty `double` )
        { : s cvf ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print cvf ) ( nurl_print ` = fptrunc double ` )
            ( nurl_print actual_fval ) ( nurl_print ` to float\n` )
            = actual_fval cvf
            = actual_fty `float` }
        {}
        ? & ( seq decl_fty `double` ) ( seq actual_fty `float` )
        { : s cvd ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print cvd ) ( nurl_print ` = fpext float ` )
            ( nurl_print actual_fval ) ( nurl_print ` to double\n` )
            = actual_fval cvd
            = actual_fty `double` }
        {}

        : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty agg_ty ) )
        ( nurl_print ` ` ) ( nurl_print result )
        ( nurl_print `, ` ) ( nurl_print ( nurl_llty actual_fty ) )
        ( nurl_print ` ` ) ( nurl_print actual_fval )
        ( nurl_print `, ` ) ( nurl_print ( nurl_str_int ins_idx ) ) ( nurl_print `\n` )
        = result r
        = idx + idx 1
    }
    ( expect lex TT_RBRACE )  // consume '}'
    // Enum-literal payload-arity check (snapshot taken above the loop;
    // idx counted the variant tag as field 0, so payloads = idx - 1).
    ? & >= enum_paycount 0 > - idx 1 enum_paycount
    { ( die lex ( nurl_str_cat3
        ( nurl_str_cat3 `enum literal supplies ` ( nurl_str_int - idx 1 ) ` payload value(s) but variant '` )
        enum_vname
        ( nurl_str_cat3 `' declares only ` ( nurl_str_int enum_paycount ) ` — if a CamelCase name in the enum declaration was meant as this variant's payload TYPE, note that an unknown/unimported type name parses as a SEPARATE variant; define or import the type before the enum.` ) ) ) }
    {}
    ( nurl_set_last_type agg_ty )
    // Borrow provenance: a freshly-constructed `@ T { … }` aggregate is
    // OWNED — never a borrow. Reset the flag so the value's last
    // sub-expression (e.g. a string_from inside) cannot leave a stale
    // borrow mark that would wrongly suppress the binding's auto-Drop.
    ( nurl_sym_def syms `__last_value_borrow__` `` )
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
    // §2.8: publish the enclosing-function parameters embedded as direct
    // fields so gen_ret can record them as returned (an aggregate that
    // embeds a parameter hands that parameter back out). A parameter
    // nested one level deeper (`@ Outer { @ Inner { cb } }`) is not in
    // this list — only a parameter that is already a stack reference
    // composes through nesting, via agg_refdepth above; an interprocedural
    // param nested inside an inner aggregate is a remaining boundary.
    ? != g_borrowck 0
    { ( nurl_sym_def syms `__last_agg_param_idents__` agg_param_idents ) } {}
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
    : ~ s vals ``
    : ~ i count 0
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
    ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_ty ) )
    ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem_ty ) ) ( nurl_print `* null, i32 ` )
    ( nurl_print ( nurl_str_int count ) ) ( nurl_print `\n` )
    : s sz_i ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print sz_i )
    ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty elem_ty ) )
    ( nurl_print `* ` ) ( nurl_print sz_gep ) ( nurl_print ` to i64\n` )
    : s raw_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print raw_ptr )
    ( nurl_print ` = call i8* @nurl_malloc(i64 ` )
    ( nurl_print sz_i ) ( nurl_print `)` ) ( emit_dbg_eol )
    // Bitcast i8* → elem_ty*
    : s typed_ptr ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print typed_ptr )
    ( nurl_print ` = bitcast i8* ` ) ( nurl_print raw_ptr )
    ( nurl_print ` to ` ) ( nurl_print ( nurl_llty elem_ty ) ) ( nurl_print `*\n` )
    // Store each value at successive GEP indices
    : ~ s rest vals
    : ~ i idx 0
    ~ < idx count {
        : s v ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s gep ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print gep )
        ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem_ty ) )
        ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem_ty ) ) ( nurl_print `* ` )
        ( nurl_print typed_ptr )
        ( nurl_print `, i32 ` ) ( nurl_print ( nurl_str_int idx ) ) ( nurl_print `\n` )
        ( nurl_print `  store ` ) ( nurl_print ( nurl_llty elem_ty ) ) ( nurl_print ` ` )
        ( nurl_print v ) ( nurl_print `, ` )
        ( nurl_print ( nurl_llty elem_ty ) ) ( nurl_print `* ` ) ( nurl_print gep ) ( nurl_print `\n` )
        = idx + idx 1
    }
    // Build { elem_ty*, i64 } slice struct
    : s slice_ty ( nurl_str_cat `{ ` ( nurl_str_cat elem_ty `*, i64 }` ) )
    : s r0 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print r0 )
    ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty slice_ty ) )
    ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty elem_ty ) ) ( nurl_print `* ` )
    ( nurl_print typed_ptr ) ( nurl_print `, 0\n` )
    : s r1 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print r1 )
    ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty slice_ty ) )
    ( nurl_print ` ` ) ( nurl_print r0 )
    ( nurl_print `, i64 ` ) ( nurl_print ( nurl_str_int count ) ) ( nurl_print `, 1\n` )
    ( nurl_set_last_type slice_ty )
    r1
}

// llvm_to_nurl: map LLVM type string to NURL type keyword for error messages.
@ llvm_to_nurl s lt → s {
    ? ( seq lt `i64` ) ^ `i`
    ? ( seq lt `i8` ) ^ `i8`
    ? ( seq lt `i1` ) ^ `b`
    ? ( seq lt `double` ) ^ `f`
    ? ( seq lt `i8*` ) ^ `s`
    // The internal repr carries signedness (A1), so the reverse map is
    // faithful for the unsigned family: `u8` is the NURL byte `u`, and
    // `u16`/`u32`/`u64` read back as themselves.
    ? ( seq lt `i16` ) ^ `i16`
    ? ( seq lt `i32` ) ^ `i32`
    ? ( seq lt `u8` ) ^ `u`
    ? ( seq lt `u16` ) ^ `u16`
    ? ( seq lt `u32` ) ^ `u32`
    ? ( seq lt `u64` ) ^ `u64`
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
    // `\ ( <compound-type> ) name → …` — the first closure param has a
    // parenthesised type, e.g. `( Vec u )` or `( @ R A )`. The token after
    // `(` introduces a type (closure-type `@`, a type keyword, a pointer/
    // option/slice/result/enum sigil, or a known type name) — none of which
    // can begin a function-call expression, so this is unambiguously a
    // closure literal and not a `\ ( call )` try-expression. (Without this,
    // only `( @ …` was recognised, so a `( Vec u )` first param fell through
    // to gen_try_expr and failed — closure params accepted fewer types than
    // function params.)
    : s t2v ( nurl_lex_peek_val lex )
    : s t2m ( nurl_sym_get syms ( nurl_str_cat t2v `__is_type` ) )
    // A type-name head after `(`: user structs/enums/generic instances carry
    // `__is_type`; `Vec` is the one pure builtin generic with no `:` def, so
    // it is named explicitly. None of these is ever a call target, so this
    // never misreads a `\ ( call )` try-expression.
    : b t2_is_type & == t2 TT_IDENT | != 0 ( nurl_str_len t2m ) ( seq t2v `Vec` )
    : b lparen_type & == t1 TT_LPAREN | | | | | | | | == t2 TT_AT == t2 TT_TYPE_KW == t2 TT_STAR == t2 TT_QUEST == t2 TT_QUESTQUEST == t2 TT_LBRACK == t2 TT_BANG == t2 TT_PIPE t2_is_type
    : b is_closure | | | | | == t1 TT_ARROW == t1 TT_TYPE_KW t1_is_type | | | == t1 TT_STAR == t1 TT_QUEST == t1 TT_LBRACK == t1 TT_BANG lparen_type & & == t1 TT_IDENT t2_is_name == t3 TT_ARROW
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
@ coerce_store_val i lex s val s from_ty s to_ty i syms i cg → s {
    // The void/unit value (a bare type keyword `v`) is never storable —
    // `: i y v` / `= x v` used to emit `store i64 void`. Reject at the source.
    ( die_if_void lex val `initialiser / assignment` )
    ? & ( seq from_ty `i1` ) ! ( seq to_ty `i1` )
    { : s r ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print r )
        ( nurl_print ` = zext i1 ` ) ( nurl_print val )
        ( nurl_print ` to ` ) ( nurl_print ( nurl_llty to_ty ) ) ( nurl_print `\n` )
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
    // Handles `: ~ MyEnum x …` mutable enum binding
    // and the symmetric immutable case. The earlier sentinel-flag-bool
    // workaround in `stdlib/ext/http_server.nu:329–360` is no longer
    // required.
    ? & == ( int_width from_ty ) 64
    & != 0 ( nurl_str_len to_ty )
    == ( nurl_str_get to_ty 0 ) 37
    { : s tname ( nurl_str_slice to_ty 1 - ( nurl_str_len to_ty ) 1 )
        : s vlist ( nurl_sym_get syms ( nurl_str_cat tname `__variants` ) )
        ? != 0 ( nurl_str_len vlist )
        { : s r ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print r )
            ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty to_ty ) )
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
                ( nurl_print ` to ` ) ( nurl_print ( nurl_llty f0_ty ) ) ( nurl_print `\n` )
                : s r ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print r )
                ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty to_ty ) )
                ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty f0_ty ) )
                ( nurl_print ` ` ) ( nurl_print p ) ( nurl_print `, 0\n` )
                ^ r }
            {} } }
    {}
    // Integer width adjustment for fixed-size types. Source and dest
    // are both integer LLVM types (i8 / i16 / i32 / i64) and the widths
    // differ. Three cases:
    //   * Narrow (from > to): emit `trunc`.
    //   * Widen, source unsigned (from_ty is `u8`/`u16`/`u32` — the
    //     type itself carries it): emit `zext`.
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
            ( nurl_print ` = trunc ` ) ( nurl_print ( nurl_llty from_ty ) )
            ( nurl_print ` ` ) ( nurl_print val )
            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty to_ty ) ) ( nurl_print `\n` )
            ^ r }
        {  // Widen direction comes from the SOURCE value's own type
            // (A1): a u8/u16/u32 source zero-extends.
            : s inst ? ( ty_is_unsigned from_ty ) `zext` `sext`
            : s r ( nurl_cg_reg cg )
            ( nurl_print `  ` ) ( nurl_print r )
            ( nurl_print ` = ` ) ( nurl_print inst ) ( nurl_print ` ` )
            ( nurl_print ( nurl_llty from_ty ) ) ( nurl_print ` ` ) ( nurl_print val )
            ( nurl_print ` to ` ) ( nurl_print ( nurl_llty to_ty ) ) ( nurl_print `\n` )
            ^ r } }
    {}
    // No coercion above bridged from_ty → to_ty. If they are a never-valid
    // mix — a float and a non-float, or a pointer/string stored into a
    // non-pointer scalar — the caller would emit `store <to_ty> <val>` with
    // disagreeing types: IR nurlc accepted (rc 0) and only clang rejected.
    // Reject at the source (covers `: i x 1.5`, `: i x `hi``, `= n 1.5`).
    // Equal types and every coercion above (i1-widen, enum-wrap, single-handle,
    // int-width; closure→fn-ptr happens next in convert_closure_arg) never
    // reach here as a clash. The reverse pointer direction (`: *T p 0`,
    // null-as-0) is intentionally allowed.
    ? & ! ( seq ( nurl_llty from_ty ) ( nurl_llty to_ty ) ) != 0 ( nurl_str_len to_ty )
    { : b csv_sf | ( seq from_ty `double` ) ( seq from_ty `float` )
        : b csv_tf | ( seq to_ty `double` ) ( seq to_ty `float` )
        ? | != csv_sf csv_tf & ( is_ptr_ty from_ty ) ! ( is_ptr_ty to_ty )
        { ( die_stmt lex ( nurl_str_cat ( nurl_str_cat4
            `value of type '` from_ty `' cannot initialise / assign a binding of type '` to_ty )
            `' — NURL has no implicit conversions; use a matching value or convert with '# T expr'` ) ) }
        {}
    }
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
        ( nurl_print ` = icmp ne ` ) ( nurl_print ( nurl_llty ty ) )
        ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, 0\n` )
        r
    }
}

// ── Closure call site helpers ───────────────────────────────────

// Convert closure struct to function pointer if needed
@ convert_closure_arg s arg_val s arg_type s expected_type i cg → s {
    // Simple type checking: check if we need to convert closure struct to function pointer
    : b is_closure_struct != 0 ( nurl_str_starts arg_type `{` )
    // Check if expected type looks like a function pointer (any return
    // type). Classify on the LOWERED spelling so a u-returning fn-ptr
    // type (`u8 (i8*)*` → `i8 (i8*)*`) is recognised too.
    : s expected_ll ( nurl_llty expected_type )
    : b starts_with_fn != 0 ( nurl_str_starts expected_ll `i64 (` )
    : b starts_with_void != 0 ( nurl_str_starts expected_ll `void (` )
    : b starts_with_i8 != 0 ( nurl_str_starts expected_ll `i8* (` )
    : b starts_with_i32 != 0 ( nurl_str_starts expected_ll `i32 (` )
    : b starts_with_dbl != 0 ( nurl_str_starts expected_ll `double (` )
    : b expects_fn_ptr | | | starts_with_fn starts_with_void starts_with_i8 | starts_with_i32 starts_with_dbl

    ? & is_closure_struct expects_fn_ptr
    {
        // Extract function pointer from closure struct (field 0)
        : s fn_ptr ( nurl_cg_reg cg )
        ( nurl_print `  ; Converting closure struct to function pointer\n` )
        ( nurl_print `  ` ) ( nurl_print fn_ptr )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty arg_type ) )
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
// Lets `=` write through a captured Counter
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

    : ~ s ty `{ i64`  // field 0: refcount
    : ~ s vars captured_vars
    ~ != 0 ( nurl_str_len vars ) {
        : s var ( str_first_word vars )
        // Lower to the LLVM spelling here: this string is pure IR text
        // (alloca/GEP/store types); the capture BINDINGS keep raw types.
        : ~ s vt ( nurl_llty ( nurl_sym_get syms var ) )
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
    : ~ s vars captured_vars
    : ~ i field_idx 1
    ~ != 0 ( nurl_str_len vars ) {
        : s var ( str_first_word vars )
        : s var_type ( nurl_sym_get syms var )
        : s var_alloca ( nurl_sym_get syms ( nurl_str_cat var `__ptr` ) )
        : b cap_byref ( __is_capture_byref var syms )

        // Effective env-field type and the value we store there.
        : s eff_type ? cap_byref ( nurl_str_cat var_type `*` ) var_type
        : ~ s loaded ( nurl_cg_reg cg )
        ? cap_byref
        {  // Store the alloca pointer itself — no load, no copy.
            = loaded var_alloca }
        {  // Existing path: load the variable's current value.
            ? != 0 ( nurl_str_len var_alloca )
            { ( nurl_print `  ` ) ( nurl_print loaded )
                ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty var_type ) )
                ( nurl_print `, ` ) ( nurl_print ( nurl_llty var_type ) )
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
        ( nurl_print `  store ` ) ( nurl_print ( nurl_llty eff_type ) ) ( nurl_print ` ` )
        ( nurl_print loaded ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty eff_type ) )
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
// __lty_base_name: the base type name of an LLVM type, with a leading '%'
// stripped and a monomorphisation suffix (`__…`) cut off — `%Rc__i64` → "Rc",
// `%Arc__i64` → "Arc", `%RcImpl__i64` → "RcImpl", `i64` → "i64".
@ __lty_base_name s lty → s {
    : i n ( nurl_str_len lty )
    : i start ? & > n 0 == ( nurl_str_get lty 0 ) 37 1 0  // '%' == 37
    : ~ i i start
    : ~ b found F
    ~ & < + i 1 n ! found {
        ? & == ( nurl_str_get lty i ) 95 == ( nurl_str_get lty + i 1 ) 95  // "__"
        { = found T } { = i + i 1 }
    }
    ? ! found { = i n } {}
    ^ ( nurl_str_slice lty start - i start )
}

// __lty_is_nonsend: true if an LLVM type is a value that is NOT safe to send
// across a thread boundary. Currently `Rc` (non-atomic refcount) — cloning or
// dropping the same Rc from two threads races on its control-block count. Its
// thread-safe counterpart is `Arc` (SEQ_CST atomic count). The check is by the
// generic base name, so every `Rc T` monomorphisation is covered while `Arc T`
// and the internal `RcImpl` are not.
@ __lty_is_nonsend s lty → b {
    ^ ( seq ( __lty_base_name lty ) `Rc` )
}

@ gen_closure_expr i lex i syms i cg → s {
    // Thread-safety side-channel (mirrors __last_closure_env__): cleared at
    // every closure build, set to a captured variable's name if that capture
    // is a non-Send value (an Rc). The enclosing `:` binding copies it to
    // `<name>__closure_nonsend`, and the thread_spawn call site reads either —
    // so capturing an Rc into a closure that is detached onto a thread is a
    // compile error, inline or via a named binding.
    = g_last_closure_nonsend ``

    // Parse parameters: type name pairs before arrow
    : ~ s param_types ``
    : ~ s param_names ``
    : ~ i param_count 0

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
        ( nurl_str_cat ( nurl_str_cat param_types `;` ) pty )
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

    // Closure-env reclamation: capturing a binding into a closure reads
    // it as a value, so a captured parameter is NOT invoke-only (§7.4) —
    // the closure may outlive the call and carry the captured reference.
    // Mark each captured name value-read in the enclosing scope.
    : ~ s __cap_scan captured_vars
    ~ != 0 ( nurl_str_len __cap_scan ) {
        : s __cap_w ( str_first_word __cap_scan )
        ( bck_mark_param_valueread syms __cap_w )
        // A tracked closure captured into THIS closure escapes — the new
        // closure (and wherever it goes) owns the captured env now.
        ( mem_own_closure_remove syms __cap_w )
        = __cap_scan ( str_skip_word __cap_scan )
    }

    // Build inline env struct type (e.g., "{ i64, i64 }") if there are captures.
    // Using inline types avoids LLVM named-struct forward-reference issues.
    : ~ s env_struct_name ``
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
    : ~ i closure_sp_id 0
    ? != g_dbg_enabled 0
    { = closure_sp_id ( dbg_emit_subprogram closure_fn_name ( nurl_lex_line lex ) ( dbg_file_for_lex lex ) )
        = g_dbg_current_subprogram closure_sp_id
        = g_dbg_current_loc ( dbg_emit_location ( nurl_lex_line lex ) 1 closure_sp_id ) }
    {}

    // Emit function header
    ( nurl_print `\ndefine ` ) ( nurl_print ( nurl_llty ret_type ) ) ( nurl_print ` @` )
    ( nurl_print closure_fn_name ) ( nurl_print `(i8* %__env` )
    : ~ s body_param_types param_types
    : ~ s body_param_names param_names
    : ~ i bi 0
    ~ < bi param_count {
        ( nurl_print `, ` )
        : s bpty ( seplist_first body_param_types )
        : s bpname ( str_first_word body_param_names )
        ( nurl_print bpty ) ( nurl_print ` %` ) ( nurl_print bpname )
        = body_param_types ( seplist_rest body_param_types )
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
    // Closure-env reclamation: shadow the enclosing function's owned-
    // closure set to empty so the closure body's own exit drain frees
    // only ITS closures — never the outer frame's (whose allocas don't
    // exist in this lifted function). Restored on sym_pop (§7.4).
    ( nurl_sym_def body_syms `__owned_closure_envs__` `` )
    ( nurl_sym_def body_syms `__in_call_arg__` `` )
    // The closure body's `^` returns from the CLOSURE, not the enclosing
    // function — shadow the return-type key with the closure's own return
    // type so gen_ret's return-value diagnostics (void-return and the
    // return-type-agreement check) compare against the right type. Restored
    // on sym_pop. Without this, `^ msg` in `\ → s { ^ msg }` was checked
    // against the enclosing fn's return type.
    ( nurl_sym_def body_syms `__fn_ret_ty__` ret_type )

    // Register closure parameters
    : ~ s bp_types param_types
    : ~ s bp_names param_names
    : ~ i bpi 0
    ~ < bpi param_count {
        : s bpname ( str_first_word bp_names )
        : s bptype ( seplist_first bp_types )
        // Alloca for each param so it can be loaded
        : s bpptr ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print bpptr )
        ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty bptype ) ) ( nurl_print `\n` )
        ( nurl_print `  store ` ) ( nurl_print ( nurl_llty bptype ) ) ( nurl_print ` %` )
        ( nurl_print bpname ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty bptype ) )
        ( nurl_print `* ` ) ( nurl_print bpptr ) ( nurl_print `\n` )
        ( nurl_sym_def body_syms bpname bptype )
        ( nurl_sym_def body_syms ( nurl_str_cat bpname `__ptr` ) bpptr )
        ( nurl_sym_def body_syms ( nurl_str_cat bpname `__param` ) `1` )
        // Mirror into the closure-local shadow-check roster.
        : s c_name_roster ( nurl_sym_get body_syms `__fn_param_names__` )
        : s c_name_next ? == 0 ( nurl_str_len c_name_roster ) bpname ( nurl_str_cat3 c_name_roster ` ` bpname )
        ( nurl_sym_def body_syms `__fn_param_names__` c_name_next )
        = bp_types ( seplist_rest bp_types )
        = bp_names ( str_skip_word bp_names )
        = bpi + bpi 1
    }

    // Register captured variables via environment struct.
    // A by-pointer capture (mutable multi-field struct) makes this
    // closure carry a pointer into the enclosing function's stack,
    // so it must NOT outlive that frame. The borrow checker's escape
    // analysis tags the closure value with a
    // *referent depth* — the deepest block scope it points into — so
    // gen_let / gen_assign / gen_ret / gen_call reject escapes
    // (docs/MEMORY.md §2.3).
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
        //     to special-case it.
        : ~ s caps captured_vars
        : ~ i cap_idx 1
        ~ != 0 ( nurl_str_len caps ) {
            : s cap_name ( str_first_word caps )
            : ~ s cap_type ( nurl_sym_get syms cap_name )
            ? == 0 ( nurl_str_len cap_type ) { = cap_type `i64` } {}
            // Thread-safety: a captured non-Send value (an Rc) makes this
            // closure unsafe to send across threads. Record the offending
            // capture; the thread_spawn call site turns it into an error.
            ? ( __lty_is_nonsend cap_type )
            { = g_last_closure_nonsend cap_name } {}
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
            ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty eff_type ) )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty eff_type ) )
            ( nurl_print `* ` ) ( nurl_print cap_gep ) ( nurl_print `\n` )
            ? cap_byref
            {  // The loaded value IS the caller's alloca pointer.
                ( nurl_sym_def body_syms cap_name cap_type )
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__ptr` ) cap_val )
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__mutable` ) `1` )
                // Mark as a by-ref capture: its storage lives in the
                // CALLER's frame (below any recover mark in this closure's
                // dynamic extent). An owned value assigned into it ESCAPES
                // the extent, so the panic-unwind journal must forget that
                // value's leaves or the drain would free what the caller
                // now owns (docs/MEMORY.md §7).
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__captured_byref` ) `1` ) }
            {  // Existing path: alloca + store so the body sees a local.
                : s cap_ptr ( nurl_cg_reg cg )
                ( nurl_print `  ` ) ( nurl_print cap_ptr )
                ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty cap_type ) ) ( nurl_print `\n` )
                ( nurl_print `  store ` ) ( nurl_print ( nurl_llty cap_type ) ) ( nurl_print ` ` )
                ( nurl_print cap_val ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty cap_type ) )
                ( nurl_print `* ` ) ( nurl_print cap_ptr ) ( nurl_print `\n` )
                ( nurl_sym_def body_syms cap_name cap_type )
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__ptr` ) cap_ptr )
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__mutable` ) `1` )
                // Mark this as a BY-VALUE capture (a snapshot into a fresh
                // per-invocation local). The body may still read/scratch it,
                // but an assignment is discarded when the closure returns and
                // never reaches the captured binding — gen_assign warns on
                // that silent dead store (the counter-closure footgun). This
                // is distinct from `__captured_byref` (a shared caller-frame
                // alloca, whose writes DO persist but which cannot escape).
                ( nurl_sym_def body_syms ( nurl_str_cat cap_name `__captured_byval` ) `1` ) }
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
        { ( nurl_print `  ret ` ) ( nurl_print ( nurl_llty ret_type ) ) ( nurl_print ` ` )
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
    : ~ s fn_ptr_type ( nurl_str_cat `{ ` ( nurl_str_cat ret_type `(` ) )
    = fn_ptr_type ( nurl_str_cat fn_ptr_type `i8*` )
    : ~ s types1 param_types
    : ~ i j 0
    ~ < j param_count {
        = fn_ptr_type ( nurl_str_cat ( nurl_str_cat fn_ptr_type `, ` ) ( seplist_first types1 ) )
        = types1 ( seplist_rest types1 )
        = j + j 1
    }
    = fn_ptr_type ( nurl_str_cat fn_ptr_type `)*, i8* }` )

    // Allocate and populate environment if there are captures
    : ~ s env_ptr `null`
    ? > captured_count 0
    {
        = env_ptr ( gen_env_allocation env_struct_name captured_vars syms cg )
    }
    {}

    // Initialize closure struct using insertvalue with undef
    : s result ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print result )
    ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty fn_ptr_type ) )
    ( nurl_print ` undef, ` ) ( nurl_print ( nurl_llty ret_type ) ) ( nurl_print `(i8*` )
    : ~ s types2 param_types
    : ~ i k 0
    ~ < k param_count {
        ( nurl_print `, ` ) ( nurl_print ( seplist_first types2 ) )
        = types2 ( seplist_rest types2 )
        = k + k 1
    }
    ( nurl_print `)* @` ) ( nurl_print closure_fn_name ) ( nurl_print `, 0\n` )

    : s result2 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print result2 )
    ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty fn_ptr_type ) )
    ( nurl_print ` ` ) ( nurl_print result ) ( nurl_print `, i8* ` )
    ( nurl_print env_ptr ) ( nurl_print `, 1\n` )

    ( nurl_set_last_type fn_ptr_type )

    // Escape analysis: advertise this closure
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

    // Closure-env reclamation: advertise this literal's heap env pointer
    // so a call site that passes the literal DIRECTLY to a borrowing
    // (non-escaping) parameter can free it after the call — the env is
    // a manually-managed handle auto-drop never owned, and a bare
    // literal has no binding to free it at scope exit (docs/MEMORY.md
    // §7.4). Only set when the closure actually captured (env != null);
    // the consuming gen_call resets this side-channel before each
    // argument and reads it after, so it never bleeds across siblings.
    ? > captured_count 0
    { ( nurl_sym_def syms `__last_closure_env__` env_ptr ) }
    { ( nurl_sym_def syms `__last_closure_env__` `` ) }

    result2
}

// ── Semicolon-separated field list ───────────────────────────────
// Closure parameter TYPES are stored joined by ';' rather than spaces,
// because an aggregate LLVM type (option `{ i1, %String }`, slice
// `{ T*, i64 }`, result, nested closure) contains its own spaces and
// commas — `str_first_word` would truncate it at the first space. ';'
// never appears in an LLVM type string, so it is a safe field delimiter.
// The n-th (0-based) element of a `;`-separated list, or `` if out of range.
@ __nth_sep s list i n → s {
    : ~ s rest list
    : ~ i k 0
    ~ < k n { = rest ( seplist_rest rest ) = k + k 1 }
    ? == 0 ( nurl_str_len rest ) { ^ `` } {}
    ^ ( seplist_first rest )
}

@ seplist_first s str → s {
    : i n ( nurl_str_len str )
    : ~ i i 0
    ~ < i n {
        ? == ( nurl_str_get str i ) 59 { ^ ( nurl_str_slice str 0 i ) } {}
        = i + i 1
    }
    ^ str
}

@ seplist_rest s str → s {
    : i n ( nurl_str_len str )
    : ~ i i 0
    ~ < i n {
        ? == ( nurl_str_get str i ) 59 { ^ ( nurl_str_slice str + i 1 - n + i 1 ) } {}
        = i + i 1
    }
    ^ ``
}

// ── String Helpers ───────────────────────────────────────────────
// Count words in a space-separated string
@ count_words s word_list → i {
    ? == 0 ( nurl_str_len word_list ) ^ 0 {}

    : ~ i count 0
    : ~ s remaining word_list
    ~ != 0 ( nurl_str_len remaining ) {
        = remaining ( str_skip_word remaining )
        = count + count 1
    }
    count
}

// Check if a space-separated word list contains a specific word
@ str_contains s word_list s target → b {
    ? == 0 ( nurl_str_len word_list ) ^ F {}

    : ~ s remaining word_list
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
    : ~ s captured_vars ``
    : ~ i captured_count 0
    ( nurl_lex_advance lex )  // consume opening '{'

    // Scan tokens in closure body until closing brace
    : ~ i brace_depth 1
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
            : ~ s code ( nurl_str_cat `  ` result )
            = code ( nurl_str_cat code ` = add i64 42, 0\n` )
            code
        }
    }
    {
        // Has captures - extract from environment and return first one
        : ~ s code ``

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
    ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty vt ) )
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
    : ~ s fail_val ? ( seq fn_rt vt ) val `zeroinitializer`
    // Result propagation where the caller's Ok type T differs from the callee's
    // (same E, enforced by T8 above): the whole-struct types disagree, so rebuild
    // the caller result `{ i1, Tc, E }` with tag 0 (Err) and the Err payload
    // (field 2) carried across by value. Without this the mismatch falls to
    // `zeroinitializer`, silently dropping the propagated error. Options (2-field)
    // and same-type results keep the cheap `val` / `zeroinitializer` path.
    ? & & ! ( seq fn_rt vt )
    & >= ( nurl_str_len fn_rt ) 6 ( seq ( nurl_str_slice fn_rt 0 6 ) `{ i1, ` )
    & == ( agg_field_count syms fn_rt ) 3 == ( agg_field_count syms vt ) 3
    { : s ev_ty ( compound_field_type vt 2 )
        : s ev ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print ev )
        ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty vt ) )
        ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, 2\n` )
        : s fe_ty ( compound_field_type fn_rt 2 )
        : s rb ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print rb )
        ( nurl_print ` = insertvalue ` ) ( nurl_print ( nurl_llty fn_rt ) )
        ( nurl_print ` zeroinitializer, ` ) ( nurl_print fe_ty )
        ( nurl_print ` ` ) ( nurl_print ev ) ( nurl_print `, 2\n` )
        = fail_val rb }
    {}
    ? != 0 ( nurl_str_len dtop )
    { ? ! ( seq fn_rt `void` )
        { : s rvp ( nurl_sym_get syms `__ret_val__` )
            ( nurl_print `  store ` ) ( nurl_print ( nurl_llty fn_rt ) )
            ( nurl_print ` ` ) ( nurl_print fail_val ) ( nurl_print `, ` )
            ( nurl_print ( nurl_llty fn_rt ) ) ( nurl_print `* ` ) ( nurl_print rvp ) ( nurl_print `\n` )
        }
        {}
        ( nurl_print `  br label %` ) ( nurl_print dtop ) ( emit_dbg_eol )
    }
    { ? ( seq fn_rt `void` )
        { ( emit_call_term `ret void` ) }
        { ( nurl_print `  ret ` ) ( nurl_print ( nurl_llty fn_rt ) )
            ( nurl_print ` ` ) ( nurl_print fail_val ) ( emit_dbg_eol )
        }
    }
    // Ok path: extract the Ok value from field 1 BY VALUE. With the wide
    // `{ i1, T, E }` layout the payload already sits at its real type T — no
    // i64 unbox / heap-load reconstruction is needed (the legacy squeeze that
    // boxed struct-handle / multi-field / wide-enum payloads is gone).
    ( emit ( nurl_str_cat lok `:` ) )
    ( nurl_sym_def syms `__cur_lbl__` lok )
    = g_did_ret 0
    : s inner_ty ( compound_field_type vt 1 )
    : s res ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print res )
    ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty vt ) )
    ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, 1\n` )
    ( nurl_set_last_type inner_ty )
    res
}

// ── Generic function helpers (Group E) ──────────────────────────────

// str_first_word: first space-delimited word in str.
@ str_first_word s str → s {
    : i slen ( nurl_str_len str )
    : ~ i pos 0
    ~ & < pos slen != ( nurl_str_get str pos ) 32 { = pos + pos 1 }
    ( nurl_str_slice str 0 pos )
}

// str_skip_word: str with first word (and following space) removed.
@ str_skip_word s str → s {
    : i slen ( nurl_str_len str )
    : ~ i pos 0
    ~ & < pos slen != ( nurl_str_get str pos ) 32 { = pos + pos 1 }
    ? & < pos slen == ( nurl_str_get str pos ) 32 { = pos + pos 1 } {}
    ( nurl_str_slice str pos - slen pos )
}

// str_contains_word: true if 'word' appears as a whole word in space-separated 'list'.
@ str_contains_word s list s word → b {
    : ~ s rest list
    ~ != 0 ( nurl_str_len rest ) {
        : s w ( str_first_word rest )
        = rest ( str_skip_word rest )
        ? ( seq w word ) { ^ T } {}
    }
    F
}

// Return the 0-based index of `word` in space-separated `list`,
// or -1 if `word` is not in `list`. Companion to str_contains_word.
@ str_word_index s list s word → i {
    : ~ s rest list
    : ~ i idx 0
    ~ != 0 ( nurl_str_len rest ) {
        : s w ( str_first_word rest )
        = rest ( str_skip_word rest )
        ? ( seq w word ) { ^ idx } {}
        = idx + idx 1
    }
    -1
}

// Auto-sink inference (critic v0.9.0 §2): when a body call moves /
// consumes an argument that is a bare parameter of the enclosing
// function, record that parameter's 0-based index for later merge
// into g_fn_sink[fname]. The merge happens in gen_fn_decl_concrete
// after the body finishes parsing. Call sites of the enclosing fn
// then see the auto-sink and reject any use-after-call of that
// argument — the indirect form of use-after-free
// (` ( wrapper x ) ( read x ) ` where wrapper frees `x` inside its
// body) becomes a borrow-checker error like the direct form already
// is. Duplicates are skipped so an explicit `sink` declaration on
// the same param is not double-listed.
@ bck_record_inferred_sink i syms s arg_name → v {
    ? == g_borrowck 0 {} {
        : s pn ( nurl_sym_get syms `__fn_param_names__` )
        : i idx ( str_word_index pn arg_name )
        ? >= idx 0
        { : s cur ( nurl_sym_get syms `__fn_inferred_sink__` )
            : s new ( nurl_str_int idx )
            ? ! ( str_contains_word cur new )
            { ( nurl_sym_def syms `__fn_inferred_sink__`
                ? == 0 ( nurl_str_len cur ) new
                ( nurl_str_cat3 cur ` ` new ) ) }
            {} }
        {}
    }
}

// Escape-summary inference (docs/MEMORY.md §2.7): when a body call
// hands a bare parameter of the enclosing function to an escaping
// argument position (a built-in heap/thread sink, or an already-known
// escaping parameter of the callee), record that parameter's 0-based
// index for merge into g_fn_escapes[fname]. Call sites of the
// enclosing function then reject passing a *stack reference* there —
// the interprocedural form of the §2.3 escape check (` ( keep ref ) `
// where `keep` stores `ref` in a container that outlives the call).
// Mirrors bck_record_inferred_sink; the merge runs in
// gen_fn_decl_concrete after the body finishes parsing.
// Closure-env reclamation (docs/MEMORY.md §7.4): record that `name` was
// loaded as a VALUE — disqualifying it from the function's invoke-only
// set. Called from gen_ident (the value-position choke point; a call's
// callee is consumed by gen_call before reaching gen_ident) and from the
// closure-capture path. NOT gated on the borrow checker: the invoke-only
// summary it feeds drives codegen, so it must be computed identically
// regardless of --no-borrowck. Cheap symbol-table append; no IR.
@ bck_mark_param_valueread i syms s name → v {
    ? == 0 ( nurl_str_len name ) { ^ v } {}
    : s cur ( nurl_sym_get syms `__fn_param_valueread__` )
    ? ( str_contains_word cur name ) {} {
        ( nurl_sym_def syms `__fn_param_valueread__`
        ? == 0 ( nurl_str_len cur ) name ( nurl_str_cat3 cur ` ` name ) ) }
}

@ bck_record_inferred_escape i syms s arg_name → v {
    ? == g_borrowck 0 {} {
        : s pn ( nurl_sym_get syms `__fn_param_names__` )
        : i idx ( str_word_index pn arg_name )
        ? >= idx 0
        { : s cur ( nurl_sym_get syms `__fn_inferred_escape__` )
            : s new ( nurl_str_int idx )
            ? ! ( str_contains_word cur new )
            { ( nurl_sym_def syms `__fn_inferred_escape__`
                ? == 0 ( nurl_str_len cur ) new
                ( nurl_str_cat3 cur ` ` new ) ) }
            {} }
        {}
    }
}

// Return-escape inference (docs/MEMORY.md §2.8): record that the
// enclosing function may RETURN this bare-identifier value when it is
// one of the function's parameters. Mirrors bck_record_inferred_escape;
// merged into g_fn_ret_param[fname] in gen_fn_decl_concrete.
@ bck_record_ret_param i syms s name → v {
    ? == g_borrowck 0 {} {
        : s pn ( nurl_sym_get syms `__fn_param_names__` )
        : i idx ( str_word_index pn name )
        ? >= idx 0
        { : s cur ( nurl_sym_get syms `__fn_ret_param__` )
            : s new ( nurl_str_int idx )
            ? ! ( str_contains_word cur new )
            { ( nurl_sym_def syms `__fn_ret_param__`
                ? == 0 ( nurl_str_len cur ) new
                ( nurl_str_cat3 cur ` ` new ) ) }
            {} }
        {}
    }
}

// idx-th space-separated word of `list`, or empty when out of range.
@ bck_nth_word s list i idx → s {
    : ~ s rest list
    : ~ i k 0
    ~ != 0 ( nurl_str_len rest ) {
        : s w ( str_first_word rest )
        = rest ( str_skip_word rest )
        ? == k idx { ^ w } {}
        = k + k 1
    }
    ``
}

// Max referent depth (docs/MEMORY.md §2.8) over the argument positions
// the callee may return: for each index in `ret_params`, look up that
// argument's recorded depth in `arg_refdepths`. 0 ⇒ the result is not a
// stack reference.
@ bck_max_ret_refdepth s ret_params s arg_refdepths → i {
    : ~ i best 0
    : ~ s rest ret_params
    ~ != 0 ( nurl_str_len rest ) {
        : s w ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s rdw ( bck_nth_word arg_refdepths ( nurl_str_to_int w ) )
        : i rd ? == 0 ( nurl_str_len rdw ) 0 ( nurl_str_to_int rdw )
        ? > rd best { = best rd } {}
    }
    best
}

// resolve_pending_escapes: replay the deferred interprocedural-escape
// checks parked by gen_call (docs/MEMORY.md §3 forward / generic) now
// that every function — including the generic instantiation flush — has
// compiled and g_fn_escapes is final. Each parked 5-tuple is
// `call_name fname arg_idx line file`; if the callee's now-known escape
// summary covers that argument index, the stack reference handed to it
// does dangle — emit the same diagnostic the inline check would have.
// A callee that turned out non-escaping resolves to nothing. Called
// once from main() after flush_deferred_instantiations.
@ resolve_pending_escapes → v {
    ? == g_borrowck 0 {} {
        : ~ s rest ( nurl_sym_get g_pending_escape `l` )
        ~ != 0 ( nurl_str_len rest ) {
            : s cn ( str_first_word rest ) = rest ( str_skip_word rest )
            : s fn ( str_first_word rest ) = rest ( str_skip_word rest )
            : s ai ( str_first_word rest ) = rest ( str_skip_word rest )
            : s ln ( str_first_word rest ) = rest ( str_skip_word rest )
            : s file ( str_first_word rest ) = rest ( str_skip_word rest )
            // Final escape summary, mangled name first then the generic
            // name (mirrors gen_call's callee_escapes lookup).
            : ~ s esc ( nurl_sym_get g_fn_escapes cn )
            ? == 0 ( nurl_str_len esc ) { = esc ( nurl_sym_get g_fn_escapes fn ) } {}
            ? ( str_contains_word esc ai ) {
                ( bck_emit_error file ( nurl_str_to_int ln ) ( nurl_str_cat3
                `passing a value that references a stack binding by pointer to '`
                fn
                `' — it escapes the current stack frame and dangles (move it to a heap-backed handle)` ) )
            } {}
        }
    }
}

// check_exhaustive: compile error if match arms don't cover all enum variants.
// ename: enum name (e.g. "Color")  seen: space-separated matched variant names
// has_wildcard: 1 if a '_' arm was present
@ check_exhaustive i lex s ename s seen i has_wildcard i syms → v {
    ? == has_wildcard 0 {
        : s all ( nurl_sym_get syms ( nurl_str_cat ename `__variants` ) )
        ? != 0 ( nurl_str_len all ) {
            : ~ s rest all
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

// __mangle_struct_esc: the escape marker prefixed onto a NAMED-struct slug
// whose bare name would otherwise collide with a builtin / compound slug.
// Must be a valid NURL identifier fragment (the mangled function name is
// re-lexed as `@ <mangled> …` in emit_one_instantiation), so no `.`/sigil.
@ __mangle_struct_esc → s { ^ `S__` }

// __mangle_slug_collides: does a NAMED struct's bare-name slug land in the
// builtin/compound slug space? `str` (i8*), `f64` (double), `i1` (b),
// `i64` (i/u64) and `void` (v) are all LEGAL struct names (none are
// lexer-reserved — only i8/i16/i32/u16/u32/u64/f32 are), and a struct may
// be named starting with `opt_` / `ptr_`. Without escaping, such a struct
// `%str` mangles to `str` — identical to the string type's slug — so two
// DISTINCT LLVM types share one monomorphisation and the second silently
// reuses the first (a layout-corrupting miscompile). We must also escape a
// name already starting with the escape marker, so the escaped space stays
// disjoint from the bare space (injectivity by induction).
@ __mangle_slug_collides s nm → b {
    ? ( seq nm `i64` ) ^ T
    ? ( seq nm `f64` ) ^ T
    ? ( seq nm `i1` ) ^ T
    ? ( seq nm `str` ) ^ T
    ? ( seq nm `void` ) ^ T
    // The unsigned internal scalars are first-class slugs since A1; a
    // user struct literally named `u8` must escape (u16/u32/u64 parse
    // as scalars and can never be struct names, but stay listed for
    // symmetry with ty_is_unsigned).
    ? ( ty_is_unsigned nm ) ^ T
    ? != 0 ( nurl_str_starts nm `opt_` ) ^ T
    ? != 0 ( nurl_str_starts nm `ptr_` ) ^ T
    ? != 0 ( nurl_str_starts nm ( __mangle_struct_esc ) ) ^ T
    ^ F
}

// mangle_type: LLVM type string → valid identifier fragment. INJECTIVE over
// LLVM type strings (see __mangle_slug_collides) so distinct generic
// instantiations never share a monomorphisation.
@ mangle_type s lty → s {
    ? ( seq lty `i64` ) ^ `i64`
    ? ( seq lty `double` ) ^ `f64`
    ? ( seq lty `i1` ) ^ `i1`
    ? ( seq lty `i8*` ) ^ `str`
    ? ( seq lty `void` ) ^ `void`
    // Option / option-of-option `{ i1, X }` → `opt_<mangle X>`. Must
    // precede the pointer + `%Name` cases. (Result is also `{ i1, i64 }`
    // but never appears as a generic type argument, so the collision is
    // harmless — it round-trips back to `?i` either way.)
    ? & >= ( nurl_str_len lty ) 8 ( seq ( nurl_str_slice lty 0 6 ) `{ i1, ` )
    ^ ( nurl_str_cat `opt_` ( mangle_type ( nurl_str_slice lty 6 - ( nurl_str_len lty ) 8 ) ) )
    {}
    ? == ( nurl_str_get lty - ( nurl_str_len lty ) 1 ) 42
    ^ ( nurl_str_cat `ptr_` ( mangle_type ( nurl_str_slice lty 0 - ( nurl_str_len lty ) 1 ) ) )
    {}
    ? == ( nurl_str_get lty 0 ) 37
    { : s nm ( nurl_str_slice lty 1 - ( nurl_str_len lty ) 1 )
        ? ( __mangle_slug_collides nm )
        { ^ ( nurl_str_cat ( __mangle_struct_esc ) nm ) } {}
        ^ nm }
    {}
    lty
}

// demangle_type: inverse of mangle_type. Maps a monomorphisation
// suffix (the slug after `__` in `vec_push__i64`, `vec_get__str`,
// `vec_new__Point`, etc.) back to a valid LLVM type string. Used by
// gen_foreach to recover the element type from a `%Vec__T` carrier
// type without re-parsing the original NURL generic. The two
// functions must round-trip: `demangle_type ( mangle_type t ) == t`
// for every t the front-end can produce.
@ demangle_type s mty → s {
    ? ( seq mty `i64` ) ^ `i64`
    ? ( seq mty `f64` ) ^ `double`
    ? ( seq mty `i1` ) ^ `i1`
    ? ( seq mty `str` ) ^ `i8*`
    ? ( seq mty `void` ) ^ `void`
    // Unsigned-int leaf slugs ARE the internal unsigned types (A1), so
    // they round-trip verbatim — gen_foreach recovers a `%Vec__u8`
    // element as `u8` and the loop binding carries its signedness in
    // its type, no separate flag needed.
    ? ( ty_is_unsigned mty ) ^ mty
    ? != 0 ( nurl_str_starts mty `opt_` )
    ^ ( nurl_str_cat `{ i1, ` ( nurl_str_cat ( demangle_type ( nurl_str_slice mty 4 - ( nurl_str_len mty ) 4 ) ) ` }` ) )
    {}
    ? != 0 ( nurl_str_starts mty `ptr_` )
    ^ ( nurl_str_cat ( demangle_type ( nurl_str_slice mty 4 - ( nurl_str_len mty ) 4 ) ) `*` )
    {}
    // Escaped NAMED-struct slug (see mangle_type): `S__<name>` → `%<name>`.
    // Strip the marker and recover the struct type. A real struct whose
    // bare name does NOT collide falls through to the plain `%mty` below.
    : s esc ( __mangle_struct_esc )
    : i el ( nurl_str_len esc )
    ? != 0 ( nurl_str_starts mty esc )
    ^ ( nurl_str_cat `%` ( nurl_str_slice mty el - ( nurl_str_len mty ) el ) )
    {}
    ( nurl_str_cat `%` mty )
}

// mangle_src_word: mangle of a generic type-ARGUMENT source word (as
// produced by capture_type_arg_src / nurl_lex_val: a base type kw, a
// named type, a `%`-stripped compound `Name__…`, or a prefix phrase
// `*u64`). Since A1 the internal type repr carries signedness, so
// `nurl_src_to_llvm` already yields distinct `u8`/`u16`/`u32`/`u64`
// leaves and mangle_type keeps them verbatim — `( gdiv [u64] )` and
// `( gdiv [i] )` monomorphise separately with no special-casing here,
// including behind `*`/`?` prefixes (`[ *u64 ]` vs `[ *i ]`, formerly a
// documented shared-slug residual).
@ mangle_src_word s w → s {
    ^ ( mangle_type ( nurl_src_to_llvm w ) )
}

// subst_source: replace whole-word occurrences of 'from' with 'to' in src.
// Words are space-separated tokens as produced by collect_fn_body.
@ subst_source s src s from s to → s {
    : ~ s result ``
    : ~ s rest src
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
    : ~ s result ``
    : i slen ( nurl_str_len src )
    : ~ i pos 0
    : ~ i word_start 0
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

// __assoc_val: look up an associated-type binding by name in an impl's
// "name1 val1 name2 val2 …" binding string. Returns the bound NURL type name,
// or "" if `name` is not bound (binding values are never empty, so "" is an
// unambiguous "absent"). No early `^` inside the loop — accumulate.
@ __assoc_val s bindings s name → s {
    : ~ s found ``
    : ~ s rest bindings
    ~ != 0 ( nurl_str_len rest ) {
        : s nm ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s vl ( str_first_word rest )
        = rest ( str_skip_word rest )
        ? ( seq nm name ) { = found vl } {}
    }
    ^ found
}

// subst_assoc: apply every associated-type binding to a default-method source,
// replacing each associated-type NAME with its impl's concrete NURL type. Run
// AFTER the trait type-param (T) substitution so a default body / signature that
// names an associated type lowers to the impl's choice (e.g. `→ Elem` → `→ i`).
@ subst_assoc s src s bindings → s {
    : ~ s result src
    : ~ s rest bindings
    ~ != 0 ( nurl_str_len rest ) {
        : s nm ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s vl ( str_first_word rest )
        = rest ( str_skip_word rest )
        = result ( subst_source_raw result nm vl )
    }
    ^ result
}

// __tok_src_text: faithful SOURCE text of the current token, for
// reconstructing a generic template that will be re-lexed at each
// instantiation. `nurl_lex_val` strips a string literal's surrounding
// backticks AND decodes its escapes, so a naive reconstruction turns
// `` `ok` `` into the bare identifier `ok` (which then fails to resolve in
// the monomorphised body). Re-wrap TT_STR in backticks and re-introduce
// the four escapes the lexer recognises (\n \t \r \\). A literal backtick
// cannot occur in the decoded content — it terminates the string — so it
// needs no escaping. Every other token type re-lexes verbatim from its val.
@ __tok_src_text i lex → s {
    : i tt ( nurl_lex_type lex )
    : s val ( nurl_lex_val lex )
    ? != tt TT_STR { ^ val } {}
    : i n ( nurl_str_len val )
    // Worst case: every byte escapes to two, plus two backticks + NUL.
    : s buf # s ( malloc + + * n 2 2 1 )
    : *u bp # *u buf
    : *u vp # *u val
    : ~ i blen 0
    = . bp blen # u 96 = blen + blen 1  // opening `
    : ~ i k 0
    ~ < k n {
        : i ch # i . vp k
        ? == ch 10 { = . bp blen # u 92 = blen + blen 1 = . bp blen # u 110 = blen + blen 1 } {
            ? == ch 9 { = . bp blen # u 92 = blen + blen 1 = . bp blen # u 116 = blen + blen 1 } {
                ? == ch 13 { = . bp blen # u 92 = blen + blen 1 = . bp blen # u 114 = blen + blen 1 } {
                    ? == ch 92 { = . bp blen # u 92 = blen + blen 1 = . bp blen # u 92 = blen + blen 1 } {
                        = . bp blen # u ch = blen + blen 1
                    } } } }
        = k + k 1
    }
    = . bp blen # u 96 = blen + blen 1  // closing `
    = . bp blen # u 0
    ^ buf
}

// collect_fn_body: collect tokens from current '{' through matching '}'.
// Returns space-separated, source-faithful token text (string literals
// keep their backticks via __tok_src_text), so the result re-lexes to the
// identical token stream — safe for generic template bodies.
@ collect_fn_body i lex → s {
    : ~ s result ( nurl_str_cat ( __tok_src_text lex ) ` ` )
    ( nurl_lex_advance lex )
    : ~ i depth 1
    ~ != depth 0 {
        : i tt2 ( nurl_lex_type lex )
        ? == tt2 TT_LBRACE { = depth + depth 1 } {}
        ? == tt2 TT_RBRACE { = depth - depth 1 } {}
        = result ( nurl_str_cat result ( nurl_str_cat ( __tok_src_text lex ) ` ` ) )
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
    {  // Substitute every type parameter with a concrete primitive (`i`)
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
    // Lint: generic fn templates are decls of the current file (the
    // scan_fn_sigs @-branch also records them, but belt-and-braces —
    // the dedup in lint_note_def makes the second call free).
    ( lint_note_def fname )
    // DWARF Phase 7: snapshot the declaration line BEFORE consuming
    // template tokens so every later instantiation can attach its
    // !DISubprogram to the original source location, not the line
    // of the synthetic `<generic>` lex emit_one_instantiation uses.
    : i src_line ( nurl_lex_line lex )
    ( nurl_sym_def g_generic_syms
    ( nurl_str_cat fname `__src_line` ) ( nurl_str_int src_line ) )
    // Defining file of the template. The instantiation flush re-parses
    // template bodies AFTER the per-file import walk has unwound, so
    // without this record the lint would attribute every symbol a
    // stdlib template's body touches to the TOP file — masking the
    // top file's own unused imports.
    ( nurl_sym_def g_generic_syms
    ( nurl_str_cat fname `__src_file` ) ( vis_current_src_file ) )
    ( expect lex TT_LBRACK )
    : ~ s tparams ``
    ~ != ( nurl_lex_type lex ) TT_RBRACK {
        : s tp ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
        = tparams ? == 0 ( nurl_str_len tparams ) tp
        ( nurl_str_cat tparams ( nurl_str_cat ` ` tp ) )
        // Optional trait bound `A: Ord`. Recorded per-tparam; checked at
        // each instantiation (the dispatch itself already works through
        // monomorphisation — the bound turns a missing impl from a
        // cryptic unresolved call into a clear diagnostic, and documents
        // the requirement). Multiple bounds via repeated `: Trait`.
        ~ == ( nurl_lex_type lex ) TT_COLON {
            ( nurl_lex_advance lex )  // consume ':'
            : s bound ( nurl_lex_val lex )
            ( nurl_lex_advance lex )  // consume trait name
            : s bkey ( nurl_str_cat3 fname `__bound__` tp )
            : s prev ( nurl_sym_get g_generic_syms bkey )
            ( nurl_sym_def g_generic_syms bkey
            ? == 0 ( nurl_str_len prev ) bound ( nurl_str_cat3 prev ` ` bound ) )
        }
    }
    ( expect lex TT_RBRACK )
    // Collect params/return/body tokens until EOF
    : ~ s src ``
    ~ & != ( nurl_lex_type lex ) TT_LBRACE != ( nurl_lex_type lex ) TT_EOF {
        = src ( nurl_str_cat src ( nurl_str_cat ( __tok_src_text lex ) ` ` ) )
        ( nurl_lex_advance lex )
    }
    ? != ( nurl_lex_type lex ) TT_EOF
    { = src ( nurl_str_cat src ( collect_fn_body lex ) ) }
    {}
    ( nurl_sym_def g_generic_syms ( nurl_str_cat fname `__tparams` ) tparams )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat fname `__gsrc` ) src )
    // Lint: names inside the stored template are references in THIS
    // file even if no instantiation ever happens (library files
    // linted standalone instantiate nothing).
    ( lint_note_template_src src ( vis_current_src_file ) )
    ( nurl_sym_def syms ( nurl_str_cat fname `__generic` ) `1` )
    // Record this generic function's `inout` / `sink`
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
    : ~ s subst_src gsrc
    : ~ s tp_rest tparams
    : ~ s ta_rest type_args
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
    : ~ s ret_ty `i64`
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

// __has_dunder: true if `str` contains "__" — the mark of a compiler-mangled
// name (a generic instantiation like `Vec__i64`, an aliased import). Such
// names are always compiler-produced, never a user-typed type name.
@ __has_dunder s str → b {
    : i n ( nurl_str_len str )
    : ~ i i 0
    ~ < i - n 1 {
        ? & == ( nurl_str_get str i ) 95 == ( nurl_str_get str + i 1 ) 95 { ^ T } {}
        = i + i 1
    }
    F
}

// check_type_known: scan an emitted LLVM type string for `%Name` references
// and reject any that names no declared type. A bare unknown type name (a
// typo, or a missing `$` import) otherwise leaks into the IR as an undefined
// `%Name` that nurlc emits with status 0 and only clang / llvm-as rejects
// ("use of undefined type named 'X'", or the cryptic "cannot allocate unsized
// type"). Accepted silently: generic type variables (tparam-like — substituted
// during monomorphisation) and compiler-mangled names (contain `__`, e.g. a
// `%Vec__i64` instantiation). `syms` carries every declared struct/enum from
// the pre-scan, so the registry lookup is reliable regardless of declaration
// order. `ctx` names the position for the diagnostic.
@ check_type_known i lex i syms s llvm_ty s ctx → v {
    : i n ( nurl_str_len llvm_ty )
    : ~ i i 0
    ~ < i n {
        ? == ( nurl_str_get llvm_ty i ) 37  // '%'
        { : ~ i j + i 1
            ~ & < j n ( __is_ident_char ( nurl_str_get llvm_ty j ) ) { = j + j 1 }
            : s name ( nurl_str_slice llvm_ty + i 1 - j + i 1 )
            // `%dyn.<Trait>` fat-pointer object type: the ident scan stops at
            // the '.', reading just `dyn`. Recognise it and skip the trailing
            // `.<Trait>` — validity (trait exists + object-safe) was already
            // checked by parse_type_dyn / gen_dyn_construct, so it is known.
            ? & ( seq name `dyn` ) & < j n == ( nurl_str_get llvm_ty j ) 46
            { = j + j 1
                ~ & < j n ( __is_ident_char ( nurl_str_get llvm_ty j ) ) { = j + j 1 } }
            { ? != 0 ( nurl_str_len name )
                { ? ( is_tparam_like name ) {}
                    { ? ( __has_dunder name ) {}
                        {  // A declared struct/enum maps to `%Name` in syms (set by
                            // the pre-scan + gen_struct/enum_decl). A bare non-empty
                            // value that does NOT start with '%' means the name is in
                            // scope as something else — an @-fn / FFI symbol / const
                            // whose value is its return/value type — and is NOT a
                            // type. Require the `%`-type form so `@ f rand x → i`
                            // (using the FFI symbol `rand` as a parameter type) is
                            // rejected too, not just a wholly-unknown name.
                            : s sv ( nurl_sym_get syms name )
                            ? & != 0 ( nurl_str_len sv ) == ( nurl_str_get sv 0 ) 37
                            {}
                            { ( die lex ( nurl_str_cat
                                ( nurl_str_cat3 `unknown type '` name `' in ` )
                                ( nurl_str_cat ctx ` — no struct or enum with this name is declared (a typo, or a missing '$' import?)` ) ) ) } } } }
                {} }
            = i j
        }
        { = i + i 1 }
    }
}

// Unknown-generic check for parse_type_paren (critic A7). Defined here
// (after the g_generic_struct_syms / g_struct_inst_syms globals) and
// forward-called from the parser: globals cannot be forward-referenced,
// functions can. Dies when `( sname … )` names a generic with no stored
// template AND no already-materialised `%sname__sfx` instantiation —
// the reference would stay an unsized opaque type and clang would
// reject it far from the real cause (usually a missing `$` import).
// Both sym handles being initialised gates out the early-boot window.
@ __die_if_unknown_generic i lex s sname s mangle_sfx → v {
    // Zero type-args (`( VtfWidget )` as a trait-impl target or any
    // parenthesised plain type) is not a generic instantiation at all —
    // nothing to size, skip.
    ? & & & != 0 ( nurl_str_len mangle_sfx )
    != 0 g_generic_struct_syms != 0 g_struct_inst_syms
    == 0 ( nurl_str_len ( nurl_sym_get g_generic_struct_syms ( nurl_str_cat sname `__stparams` ) ) )
    { : s done_chk ( nurl_str_cat sname ( nurl_str_cat mangle_sfx `__done` ) )
        ? == 0 ( nurl_str_len ( nurl_sym_get g_struct_inst_syms done_chk ) )
        { ( die lex ( nurl_str_cat3 `unknown generic type '( ` ( nurl_str_cat sname ` … )` )
            `' — no generic struct of that name is defined or imported here, so the type cannot be sized. Missing a '$' import (stdlib/core/vec.nu for Vec)?` ) ) }
        {}
    }
    {}
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
            : ~ s mangled sname
            : ~ s tp_r tparams
            : ~ s ta_r ta_list
            ~ & != 0 ( nurl_str_len tp_r ) != 0 ( nurl_str_len ta_r ) {
                : s tp ( str_first_word tp_r )
                = tp_r ( str_skip_word tp_r )
                : s ta ( str_first_word ta_r )
                = ta_r ( str_skip_word ta_r )
                = mangled ( nurl_str_cat mangled
                ( nurl_str_cat `__` ( mangle_src_word ta ) ) )
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
                    // flt is the SUBSTITUTED field's raw internal type —
                    // signedness included (`( Pair u64 i )` records a
                    // `u64` field), mirroring gen_struct_decl.
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
                    { ( nurl_print ( nurl_llty flt ) ) = first 0 }
                    { ( nurl_print `, ` ) ( nurl_print ( nurl_llty flt ) ) }
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
@ defer_instantiation i lex s fname s mangled s type_args i syms → v {
    // Critic v0.9.0 §2: capture the call site so emit_one_instantiation
    // can render `<generic vec_as_slice__i64 from user.nu:42>:1:21:` in
    // any diagnostic emitted while re-parsing the substituted body,
    // instead of the opaque `<generic>:1:21:`.
    : s caller_file ( nurl_lex_filename lex )
    : i caller_line ( nurl_lex_line lex )
    : s ret_ty ( compute_generic_ret_ty fname type_args )
    ( nurl_sym_def syms mangled ret_ty )
    : s cnt_s ( nurl_sym_get g_generic_syms `__deferred_count__` )
    : i n ( nurl_str_to_int cnt_s )
    ( nurl_sym_def g_generic_syms `__deferred_count__` ( nurl_str_int + n 1 ) )
    : s base ( nurl_str_cat `__def` ( nurl_str_int n ) )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat base `_fn` ) fname )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat base `_mn` ) mangled )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat base `_ta` ) type_args )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat base `_cf` ) caller_file )
    ( nurl_sym_def g_generic_syms ( nurl_str_cat base `_cl` ) ( nurl_str_int caller_line ) )
}

// emit_str_globals: emit global constants for string literals [base..top).
@ emit_str_globals i base i top → v {
    : i sg g_str_syms
    : ~ i k base
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

// ── Entry-block alloca hoisting ─────────────────────────────────────
// NURL emits each `:` binding's `alloca` at its lexical position. LLVM
// alloca lifetime is the WHOLE function (the slot is freed only at
// `ret`), so an alloca inside a loop allocates a FRESH slot every
// iteration and never reclaims it — a hot loop over N items leaks N
// stack slots and overflows the stack. clang's mem2reg/SROA promotes
// these (single-store) allocas to SSA values and silently hides the
// leak; other LLVM front-ends (notably the zig-bundled toolchain used
// by the installed releases) keep the dynamic stack adjustment and
// crash with a stack overflow on large inputs (e.g. gzip/deflate over a
// multi-KB buffer). The fix is the canonical LLVM idiom: emit every
// alloca in the entry block. All NURL allocas are static-size with no
// SSA operands, so hoisting is always valid and semantically identical
// — the slot's lifetime is already function-wide either way; we only
// stop re-issuing it per iteration.

// Index of the '\n' ending the line starting at `p`, or `flen` if the
// text has no further newline.
@ __ha_line_end s text i p i flen → i {
    : ~ i q p
    ~ < q flen {
        ? == ( nurl_str_get text q ) 10 { ^ q } {}
        = q + q 1
    }
    ^ flen
}

// True when `line` is an alloca INSTRUCTION (`  %reg = alloca <ty>`).
// Guards on the `  %` register-define prefix so a stray ` = alloca ` in
// some other context cannot match; the type is always static (no count
// operand, no SSA reference), which is what makes hoisting sound.
@ __ha_is_alloca s line → b {
    ? < ( strlen line ) 3 { ^ F } {}
    ? != ( nurl_str_get line 0 ) 32 { ^ F } {}
    ? != ( nurl_str_get line 1 ) 32 { ^ F } {}
    ? != ( nurl_str_get line 2 ) 37 { ^ F } {}
    ^ ? >= ( nurl_str_find line ` = alloca ` ) 0 T F
}

// Re-print a complete `define … { entry: … }` IR string with every
// alloca instruction moved to the top of the entry block (original
// relative order preserved); all other instructions — including each
// alloca's matching `store` — stay exactly where they were. A function
// with no `entry:` label (should not happen) is emitted verbatim.
@ emit_hoisted s funcdef → v {
    : i flen ( strlen funcdef )
    : i ei ( nurl_str_find funcdef `\nentry:\n` )
    ? < ei 0 { ( nurl_print funcdef ) ^ v } {}
    : i hdr_end + ei 8  // past "\nentry:\n"
    ( nurl_print ( nurl_str_slice funcdef 0 hdr_end ) )
    // Pass 1: the alloca instructions, hoisted into the entry block.
    : ~ i p hdr_end
    ~ < p flen {
        : i le ( __ha_line_end funcdef p flen )
        : s line ( nurl_str_slice funcdef p - le p )
        ? ( __ha_is_alloca line ) { ( nurl_print line ) ( nurl_print `\n` ) } {}
        = p + le 1
    }
    // Pass 2: everything else, in original order.
    = p hdr_end
    ~ < p flen {
        : i le ( __ha_line_end funcdef p flen )
        : s line ( nurl_str_slice funcdef p - le p )
        ? ! ( __ha_is_alloca line ) { ( nurl_print line ) ( nurl_print `\n` ) } {}
        = p + le 1
    }
}

// emit_closure_globals: emit only NEW deferred closure definitions since last call
@ emit_closure_globals → v {
    // Emit new closure function definitions (from watermark to current)
    : i defs_syms g_closure_defs
    : ~ i idx g_closure_emit_base
    ~ < idx g_func_count {
        : s funcdef ( nurl_sym_get defs_syms ( nurl_str_int idx ) )
        ? != 0 ( nurl_str_len funcdef )
        { ( emit_hoisted funcdef ) }
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
        // Lint: snapshot the name token's position before advancing past
        // it (used by the unused-function report's warning location).
        : i lint_fn_line ( nurl_lex_line lex )
        : i lint_fn_col ( nurl_lex_col lex )
        ( nurl_lex_advance lex )
        // Grammar v2.0: re-record (idempotent) the source-file + public
        // flag during the parse_program pass. scan_fn_sigs has already
        // populated g_vis_syms; calling here ensures g_pending_pub is
        // cleared so a stray `pub` doesn't leak to a later decl.
        ( vis_record_fn fname ( vis_take_pending_pub ) )
        ( lint_note_fn lex fname lint_fn_line lint_fn_col )
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
            // Bounded tparam list `[A: Trait …]`. A slice param's type
            // never contains a `:`, so a colon anywhere in the bracket
            // (within peek range) unambiguously marks a generic. Covers
            // `[A: Ord]`, `[A B: Hash]`, `[A: Ord B]`, `[A B C: H]`.
            : i p4c ( nurl_lex_peek4_type lex )
            : b genb & is_name1 | | == p2 TT_COLON == p3 TT_COLON == p4c TT_COLON
            ? | | | gen1 gen2 gen3 genb
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
    ( lint_fn_begin )
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
    // Borrow provenance: does THIS function return a borrow (a value that
    // aliases a parameter)? Set by gen_ret from __last_value_borrow__.
    ( nurl_sym_def syms `__fn_ret_borrow__` `` )
    ? != 0 g_auto_drop_strings
    { ( nurl_sym_def syms `__owned_strings__` `` )
        ( nurl_sym_def syms `__owned_struct_fields__` `` )
        ( nurl_sym_def syms `__user_drops__` `` )
        ( nurl_sym_def syms `__fn_ret_str_owned__` `` )
        ( nurl_sym_def syms `__fn_ret_struct_owned__` `` )
    }
    {}
    : ~ s params_str ``
    : ~ i pct 0
    // Accumulate the 0-based indices of `inout`
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
    // gen_let_or_struct's shadow check. Closures
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
    // Publish this function's inout / sink
    // parameter sets (empty for an ordinary function — harmless,
    // gen_call treats an empty / absent entry the same).
    ( nurl_sym_def g_fn_inout fname inout_acc )
    ( nurl_sym_def g_fn_sink fname sink_acc )
    ( expect lex TT_ARROW )
    // Reset last_res_nurl / last_res_t_llvm so we can detect if
    // parse_type_res ran for this return type (only result types set them).
    ( nurl_sym_def g_res_type_syms `__last_res_nurl__` `` )
    ( nurl_sym_def g_res_type_syms `__last_res_t_llvm__` `` )
    ( nurl_sym_def g_res_type_syms `__last_res_err_llvm__` `` )
    ( nurl_sym_def g_res_type_syms `__last_opt_nurl_t__` `` )
    : s ret_ty ( parse_type lex )
    ( check_type_known lex syms ret_ty `the return type` )
    : s nurl_ret ( nurl_sym_get g_res_type_syms `__last_res_nurl__` )
    // LLVM type of the Ok-payload T (e.g. `%Vec__i8` for `! ( Vec u ) s`,
    // `i8*` for `! s E`). Recorded per-function — mirrors `<fname>__nurl_ret`
    // — so a `?? ( call ) { … }` whose scrutinee is a DIRECT CALL (no
    // binding to hang `<name>__res_t_llvm` off, the way gen_let_or_struct
    // does for `?? r`) can still reconstruct a single-pointer-handle or
    // pointer payload in the T-arm. Empty for non-result returns.
    : s res_t_llvm ( nurl_sym_get g_res_type_syms `__last_res_t_llvm__` )
    // LLVM type of the Err-payload E — the F-arm counterpart of res_t_llvm,
    // for an `F e → e` arm whose E is a bare pointer (`! T s`). Enum errors
    // resolve via their NURL name and don't need this; it only fills the
    // gap for pointer / paren-compound error payloads.
    : s res_e_llvm ( nurl_sym_get g_res_type_syms `__last_res_err_llvm__` )
    // Inner NURL type token of a `? T` return (e.g. `u`), for the direct-
    // call option-match signedness path. Empty for non-option returns.
    : s opt_nurl_t ( nurl_sym_get g_res_type_syms `__last_opt_nurl_t__` )
    ( nurl_sym_def syms fname ret_ty )
    ( nurl_sym_def syms `__fn_ret_ty__` ret_ty )
    // Store NURL return type for try-propagation type checking
    ( nurl_sym_def syms `__fn_nurl_ret__` nurl_ret )
    ( nurl_sym_def syms ( nurl_str_cat fname `__nurl_ret` ) nurl_ret )
    ( nurl_sym_def syms ( nurl_str_cat fname `__res_t_llvm` ) res_t_llvm )
    ( nurl_sym_def syms ( nurl_str_cat fname `__res_e_llvm` ) res_e_llvm )
    ( nurl_sym_def syms ( nurl_str_cat fname `__opt_nurl_t` ) opt_nurl_t )
    : s lname ? ( seq fname `main` ) `_nurl_main` fname
    // Capture the whole function definition into the output buffer so its
    // allocas can be hoisted into the entry block before emission (see
    // emit_hoisted). Closures created mid-body buffer separately (nested
    // print_buf frames) and string/debug globals are deferred, so only
    // this function's own IR lands in the buffer.
    ( nurl_print_buf_start )
    ( nurl_print `define ` ) ( nurl_print ( nurl_llty ret_ty ) )
    ( nurl_print ` @` ) ( nurl_print lname )
    ( nurl_print `(` ) ( nurl_print params_str ) ( nurl_print `)` )
    // DWARF: attach `!dbg !N` to the define line (referencing this fn's
    // !DISubprogram) and seed g_dbg_current_loc with a DILocation at
    // fn-entry. emit_dbg_eol then attaches `!dbg` to every call/ret/br
    // inside the body. Both globals reset to 0 after the closing `}`.
    ? != g_dbg_enabled 0
    { : i fn_fid ( dbg_file_for_lex lex )
        : i sp_id ( dbg_emit_subprogram lname fn_src_line fn_fid )
        : i loc_id ( dbg_emit_location fn_src_line 1 sp_id )
        = g_dbg_current_subprogram sp_id
        = g_dbg_current_file_id fn_fid
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
    : ~ s ret_val_ptr ``
    ? ! ( seq ret_ty `void` )
    { : s p ( nurl_cg_reg cg )
        ( nurl_print `  ` ) ( nurl_print p )
        ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty ret_ty ) ) ( nurl_print `\n` )
        ( nurl_sym_def syms `__ret_val__` p )
        = ret_val_ptr p
    }
    {}
    : i base_str g_str_idx
    // Auto-sink inference (critic v0.9.0 §2): reset the side-channel
    // accumulator before the body parses. gen_call's destructor- and
    // sink-arg paths append param indices via bck_record_inferred_sink
    // when the consumed arg is a bare parameter of THIS function. The
    // merge into g_fn_sink[fname] happens after the body finishes.
    ( nurl_sym_def syms `__fn_inferred_sink__` `` )
    // Escape-summary inference (docs/MEMORY.md §2.7): same shape — reset
    // the accumulator; gen_call appends param indices that reach an
    // escaping argument position; merged into g_fn_escapes[fname] below.
    ( nurl_sym_def syms `__fn_inferred_escape__` `` )
    // Invoke-only inference (docs/MEMORY.md §7.4): reset the value-read
    // accumulator; gen_ident / the capture path append a parameter name
    // whenever it is loaded as a value; the complement (params never
    // value-loaded) becomes g_fn_invoke_only[fname] after the body.
    ( nurl_sym_def syms `__fn_param_valueread__` `` )
    // Closure-env reclamation (docs/MEMORY.md §7.4): reset the per-function
    // owned-closure-env set; gen_let registers a capturing `: f \ …`
    // binding, escape sites remove it, the function-exit drain frees the
    // survivors.
    ( nurl_sym_def syms `__owned_closure_envs__` `` )
    ( nurl_sym_def syms `__in_call_arg__` `` )
    // Return-escape inference (docs/MEMORY.md §2.8): gen_ret appends the
    // index of any parameter returned directly; merged into
    // g_fn_ret_param[fname] after the body.
    ( nurl_sym_def syms `__fn_ret_param__` `` )
    : s last ( gen_block_ret lex syms cg )
    // Borrow provenance for an IMPLICIT (no `^`) block return: the body's
    // final expression IS the return value, so if it left a borrow on
    // __last_value_borrow__ (e.g. a `?? param { … }` yielding a payload
    // view), this function returns a borrow. Mirrors the explicit-`^`
    // gen_ret. (gen_ret also sets the flag, so this only ADDS the
    // implicit case; idempotent for explicit returns.)
    ? != 0 ( nurl_str_len ( nurl_sym_get syms `__last_value_borrow__` ) )
    { ( nurl_sym_def syms `__fn_ret_borrow__` `1` ) }
    {}
    // Auto-sink inference (critic v0.9.0 §2): merge any inferred sinks
    // into g_fn_sink[fname], deduping against the explicit `sink`
    // marker set already published above.
    : s __as_inferred ( nurl_sym_get syms `__fn_inferred_sink__` )
    ? != 0 ( nurl_str_len __as_inferred )
    { : ~ s __as_merged ( nurl_sym_get g_fn_sink fname )
        : ~ s __as_rest __as_inferred
        ~ != 0 ( nurl_str_len __as_rest ) {
            : s __as_w ( str_first_word __as_rest )
            = __as_rest ( str_skip_word __as_rest )
            ? ! ( str_contains_word __as_merged __as_w )
            { = __as_merged ? == 0 ( nurl_str_len __as_merged )
                __as_w
                ( nurl_str_cat3 __as_merged ` ` __as_w ) }
            {} }
        ( nurl_sym_def g_fn_sink fname __as_merged ) }
    {}
    // Escape-summary inference (docs/MEMORY.md §2.7): merge inferred
    // escaping-parameter indices into g_fn_escapes[fname]. Same merge
    // shape as the auto-sink block above.
    : s __ae_inferred ( nurl_sym_get syms `__fn_inferred_escape__` )
    ? != 0 ( nurl_str_len __ae_inferred )
    { : ~ s __ae_merged ( nurl_sym_get g_fn_escapes fname )
        : ~ s __ae_rest __ae_inferred
        ~ != 0 ( nurl_str_len __ae_rest ) {
            : s __ae_w ( str_first_word __ae_rest )
            = __ae_rest ( str_skip_word __ae_rest )
            ? ! ( str_contains_word __ae_merged __ae_w )
            { = __ae_merged ? == 0 ( nurl_str_len __ae_merged )
                __ae_w
                ( nurl_str_cat3 __ae_merged ` ` __ae_w ) }
            {} }
        ( nurl_sym_def g_fn_escapes fname __ae_merged ) }
    {}
    // Invoke-only inference (docs/MEMORY.md §7.4): a parameter never
    // loaded as a value (only ever a call's callee, or unused) is a pure
    // borrow — record its index in g_fn_invoke_only[fname] so a caller
    // may free an inline closure literal's env after handing it here.
    // Authoritative per function (overwrite, not merge): the value-read
    // set is complete once the body is compiled.
    : s __io_vr ( nurl_sym_get syms `__fn_param_valueread__` )
    : ~ s __io_names ( nurl_sym_get syms `__fn_param_names__` )
    : ~ i __io_idx 0
    : ~ s __io_set ``
    ~ != 0 ( nurl_str_len __io_names ) {
        : s __io_p ( str_first_word __io_names )
        = __io_names ( str_skip_word __io_names )
        ? ! ( str_contains_word __io_vr __io_p )
        { : s __io_w ( nurl_str_int __io_idx )
            = __io_set ? == 0 ( nurl_str_len __io_set ) __io_w ( nurl_str_cat3 __io_set ` ` __io_w ) }
        {}
        = __io_idx + __io_idx 1
    }
    ( nurl_sym_def g_fn_invoke_only fname __io_set )
    // Return-escape inference (docs/MEMORY.md §2.8): merge returned-
    // parameter indices into g_fn_ret_param[fname]. Same merge shape.
    : s __rp_inferred ( nurl_sym_get syms `__fn_ret_param__` )
    ? != 0 ( nurl_str_len __rp_inferred )
    { : ~ s __rp_merged ( nurl_sym_get g_fn_ret_param fname )
        : ~ s __rp_rest __rp_inferred
        ~ != 0 ( nurl_str_len __rp_rest ) {
            : s __rp_w ( str_first_word __rp_rest )
            = __rp_rest ( str_skip_word __rp_rest )
            ? ! ( str_contains_word __rp_merged __rp_w )
            { = __rp_merged ? == 0 ( nurl_str_len __rp_merged )
                __rp_w
                ( nurl_str_cat3 __rp_merged ` ` __rp_w ) }
            {} }
        ( nurl_sym_def g_fn_ret_param fname __rp_merged ) }
    {}
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
    : ~ s skip_str_ptr ``
    : ~ s skip_user_ptr ``
    ? != 0 g_auto_drop_strings
    { : s rid_ptr ( nurl_sym_get syms ( nurl_str_cat ret_ident `__ptr` ) )
        = skip_str_ptr ? & ( seq ( nurl_llty ret_ty ) `i8*` ) ( str_contains_word ( nurl_sym_get syms `__owned_strings__` ) rid_ptr )
        rid_ptr
        ``
        ? != 0 ( nurl_str_len skip_str_ptr )
        { ( nurl_sym_def syms `__fn_ret_str_owned__` `1` ) }
        {}
        // A void fall-off returns nothing — no binding can escape
        // through it, so a stale __last_ident_name__ (e.g. the last
        // call's argument) must not cancel a Drop-value's drop here.
        = skip_user_ptr ? & ! ( seq ret_ty `void` )
        ( str_contains_word ( nurl_sym_get syms `__user_drops__` ) rid_ptr )
        rid_ptr
        ``
    }
    {}
    // A4c: owned-struct-field transfer for the implicit (fall-off) return.
    : ~ s skip_struct_ptr ``
    ? != 0 g_auto_drop_strings
    { = skip_struct_ptr ( mem_ret_struct_transfer syms ret_ty ret_ident ) }
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
                    ( mem_drop_owned_struct_fields syms cg skip_struct_ptr )
                    ( mem_drop_user_drops syms cg skip_user_ptr )
                }
                {}
                ( mem_drop_closure_envs syms cg )
                ( emit_call_term `ret void` ) }
        }
        {}
    }
    { ? == g_did_ret 0
        { ? != 0 ( nurl_str_len dtop )
            { ( nurl_print `  store ` ) ( nurl_print ( nurl_llty ret_ty ) ) ( nurl_print ` ` )
                ( nurl_print last ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty ret_ty ) )
                ( nurl_print `* ` ) ( nurl_print ret_val_ptr ) ( nurl_print `\n` )
                ( nurl_print `  br label %` ) ( nurl_print dtop ) ( emit_dbg_eol )
            }
            { ( mem_drop_owned syms cg skip )
                ? != 0 g_auto_drop_strings
                { ( mem_drop_owned_strings syms cg skip_str_ptr )
                    ( mem_drop_owned_struct_fields syms cg skip_struct_ptr )
                    ( mem_drop_user_drops syms cg skip_user_ptr )
                }
                {}
                // Return-escape: an implicitly-returned closure binding
                // hands its env to the caller — do not free it here.
                ( mem_own_closure_remove syms ret_ident )
                ( mem_drop_closure_envs syms cg )
                ( nurl_print `  ret ` ) ( nurl_print ( nurl_llty ret_ty ) )
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
            ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty ret_ty ) )
            ( nurl_print `, ` ) ( nurl_print ( nurl_llty ret_ty ) )
            ( nurl_print `* ` ) ( nurl_print ret_val_ptr ) ( nurl_print `\n` )
            ( nurl_print `  ret ` ) ( nurl_print ( nurl_llty ret_ty ) )
            ( nurl_print ` ` ) ( nurl_print rv ) ( emit_dbg_eol )
        }
        { ( emit_call_term `ret void` ) }
    }
    {}
    ( emit `}` ) ( emit `` )
    // Stop capturing and re-emit with allocas hoisted into the entry block.
    : s __fn_ir ( nurl_print_buf_stop )
    ( emit_hoisted __fn_ir )
    // Clear DWARF state — subsequent module-scope code (string globals,
    // closure defs, the next function's metadata) must not inherit
    // this function's DILocation, or its calls would attach `!dbg !N`
    // referencing a stale scope. Reset to 0; emit_dbg_eol then degrades
    // to a plain `\n` until the next function sets it again.
    = g_dbg_current_subprogram 0
    = g_dbg_current_file_id 0
    = g_dbg_current_loc 0
    ( emit_str_globals base_str g_str_idx )
    ( emit_closure_globals )
    // Borrow checker: the function body is fully parsed —
    // run the analysis pass before the scope is popped. No-op unless
    // --borrowck is set; never emits IR.
    ( borrowck_fn_end lex syms fname )
    // Lint: warn for this function's `:` bindings that were never read.
    ( lint_fn_end lex )
    // Snapshot owned-return flags BEFORE pop: nurl_sym_get returns a pointer
    // into the current scope's entry, which nurl_sym_pop then frees.
    : i fn_ret_owned_flag ? != 0 ( nurl_str_len ( nurl_sym_get syms `__fn_ret_owned__` ) ) 1 0
    : i fn_ret_str_owned_flag ? != 0 g_auto_drop_strings
    ? != 0 ( nurl_str_len ( nurl_sym_get syms `__fn_ret_str_owned__` ) ) 1 0
    0
    : i fn_ret_borrow_flag ? != 0 ( nurl_str_len ( nurl_sym_get syms `__fn_ret_borrow__` ) ) 1 0
    // A4c: snapshot the returned struct's owned-field list (colon format)
    // BEFORE the pop frees the scope entry. Empty unless this function
    // returns a by-value struct with fresh-owned fields.
    : s fn_ret_struct_fields ? != 0 g_auto_drop_strings
    ( nurl_str_cat ( nurl_sym_get syms `__fn_ret_struct_owned__` ) `` )
    ``
    ( nurl_sym_pop syms )
    ( nurl_sym_def syms fname ret_ty )
    // Re-store NURL ret type in outer scope (inner scope was just popped)
    ( nurl_sym_def syms ( nurl_str_cat fname `__nurl_ret` ) nurl_ret )
    ( nurl_sym_def syms ( nurl_str_cat fname `__res_t_llvm` ) res_t_llvm )
    ( nurl_sym_def syms ( nurl_str_cat fname `__res_e_llvm` ) res_e_llvm )
    ( nurl_sym_def syms ( nurl_str_cat fname `__opt_nurl_t` ) opt_nurl_t )
    // Persist "returns owned X" flag: "1" = slice, "str" = string.
    // A function returns at most one kind of owned value, so one sideband
    // key suffices. When Phase 2B is off `fn_ret_str_owned_flag` is always 0.
    ? != 0 fn_ret_str_owned_flag
    { ( nurl_sym_def syms ( nurl_str_cat fname `__ret_owned` ) `str` ) }
    { ? != 0 fn_ret_owned_flag
        { ( nurl_sym_def syms ( nurl_str_cat fname `__ret_owned` ) `1` ) }
        {}
    }
    // Persist "returns a borrow" so a caller's `:`-binding off this fn
    // skips its auto-Drop (borrow-provenance pass).
    ? != 0 fn_ret_borrow_flag
    { ( nurl_sym_def syms ( nurl_str_cat fname `__ret_borrow` ) `1` ) }
    {}
    // A4c: persist the returned struct's owned-field list so a caller's
    // `: T x ( fname )` re-registers exactly those fields for drop.
    ? != 0 ( nurl_str_len fn_ret_struct_fields )
    { ( nurl_sym_def syms ( nurl_str_cat fname `__ret_owned_fields` ) fn_ret_struct_fields ) }
    {}
    ? ( seq fname `main` ) ( emit_main_wrapper ret_ty ) {}
}

// Parse one parameter; return accumulated params_str via nurl_set_last_type.
// parse_type handles base types, pointer types, and all compound types.
// Consume an optional parameter-convention marker. Returns the
// convention:
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
    // `__last_param_inout__` / `__last_param_sink__` report back to
    // gen_fn_decl_concrete which convention this parameter used, so
    // it can record the function's inout / sink index sets in
    // g_fn_inout / g_fn_sink.
    ( nurl_sym_def syms `__last_param_inout__` `` )
    ( nurl_sym_def syms `__last_param_sink__` `` )
    // Optional in/inout/sink convention marker. A `sink` parameter
    // consumes its argument; codegen-wise it is an ordinary by-value
    // parameter (the convention is enforced at the call site —
    // gen_call move-marks the argument), so it needs no special
    // handling here beyond the side-channel below.
    : i pconv ( parse_param_marker lex )
    // Reset the result/option side-channels so a `! T E` / `? T` parameter
    // type leaves fresh metadata here (and a non-result param doesn't
    // inherit a previous param's stale values). Mirrors the resets
    // gen_fn_decl_concrete does before parsing the return type.
    ( nurl_sym_def g_res_type_syms `__last_res_nurl__` `` )
    ( nurl_sym_def g_res_type_syms `__last_res_t_llvm__` `` )
    ( nurl_sym_def g_res_type_syms `__last_res_err_llvm__` `` )
    ( nurl_sym_def g_res_type_syms `__last_opt_nurl_t__` `` )
    : s lt ( parse_type lex )
    ( check_type_known lex syms lt `a parameter type` )
    // Capture the `! T E` / `? T` payload metadata for this parameter so a
    // `?? <param> { T x → … }` match can reconstruct a struct / pointer
    // payload from its i64 slot — exactly as gen_let_or_struct does for a
    // let-bound result var. Without this a struct-typed T-arm binding on a
    // result PARAMETER stayed a raw i64 (miscompiled `^ x` to `ret i64`).
    : s p_res_nurl ( nurl_sym_get g_res_type_syms `__last_res_nurl__` )
    : s p_res_t_llvm ( nurl_sym_get g_res_type_syms `__last_res_t_llvm__` )
    : s p_res_e_llvm ( nurl_sym_get g_res_type_syms `__last_res_err_llvm__` )
    : s p_opt_nurl_t ( nurl_sym_get g_res_type_syms `__last_opt_nurl_t__` )
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { : s pname ( nurl_lex_val lex )
        // Reject parameter names that collide with LLVM reserved basic-
        // block labels. Every NURL function emits an `entry:` block as
        // its first label; a param named `entry` then collides at
        // `%entry` lookup time and the bootstrap compiler emits a
        // cryptic "unable to create block named 'entry'" LLVM error
        // far from the source.
        ? ( seq pname `entry` )
        { ( die lex `parameter name 'entry' collides with LLVM's reserved entry: block label. Rename (e.g. 'ent', 'tab_entry').` ) }
        {}
        // `inout` is a parameter-convention keyword; banning it as
        // a parameter NAME keeps the scan_fn_sigs forward-reference
        // check (`<fname>__has_inout`) exact.
        ? ( seq pname `inout` )
        { ( die lex `parameter name 'inout' is a reserved convention keyword - rename it` ) }
        {}
        ( nurl_lex_advance lex )
        // Default value `= <single-token>` (keyword-args). The callee does
        // not use it — callers splice it for omitted arguments — so here
        // we only consume the tokens. Only fires when `=` is present.
        ? == ( nurl_lex_type lex ) TT_EQ
        { ( nurl_lex_advance lex ) ( nurl_lex_advance lex ) }
        {}
        ( nurl_sym_def syms pname lt )
        // Mark parameter as immutable by design
        ( nurl_sym_def syms ( nurl_str_cat pname `__param` ) `1` )
        // Borrow-provenance origin: an auto-Drop enum parameter is a
        // BORROW (the caller owns it). Values derived from it (vec_get,
        // field access, returned through it) inherit `__borrow`, so a
        // caller's `:`-binding off a borrow-returning accessor skips its
        // auto-drop instead of double-freeing the still-owned source.
        ? & == pconv 0 ( __is_autodrop_enum lt syms )
        { ( nurl_sym_def syms ( nurl_str_cat pname `__borrow` ) `1` ) }
        {}
        // An `inout` parameter is an exclusive mutable borrow. It
        // lowers to the `*T`-by-address
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
        // Stash `! T E` / `? T` payload metadata for this parameter, mirroring
        // gen_let_or_struct, so a `?? <param>` match can reconstruct a struct /
        // pointer / unsigned payload binding rather than leaving it a raw i64.
        ? != 0 ( nurl_str_len p_res_nurl )
        { : s pinner_t ( str_first_word ( str_skip_word p_res_nurl ) )
            : s pinner_e ( str_first_word ( str_skip_word ( str_skip_word p_res_nurl ) ) )
            ( nurl_sym_def syms ( nurl_str_cat pname `__res_nurl_T` ) pinner_t )
            ( nurl_sym_def syms ( nurl_str_cat pname `__res_nurl_E` ) pinner_e ) }
        {}
        ? != 0 ( nurl_str_len p_res_t_llvm )
        { ( nurl_sym_def syms ( nurl_str_cat pname `__res_t_llvm` ) p_res_t_llvm ) }
        {}
        ? != 0 ( nurl_str_len p_res_e_llvm )
        { ( nurl_sym_def syms ( nurl_str_cat pname `__res_e_llvm` ) p_res_e_llvm ) }
        {}
        ? != 0 ( nurl_str_len p_opt_nurl_t )
        { ( nurl_sym_def syms ( nurl_str_cat pname `__opt_nurl_T` ) p_opt_nurl_t ) }
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
        // An `inout` parameter's LLVM type is a pointer to T. The
        // signature text is IR — lower the internal type here; the
        // binding registered above keeps the raw spelling.
        : s entry ? == pconv 1
        ( nurl_str_cat4 ( nurl_llty lt ) `* %` pname `` )
        ( nurl_str_cat3 ( nurl_llty lt ) ` %` pname )
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
// Closes the field-mutation half (struct by-value / inout) for the
// function-parameter case (previously the closure capture half was
// closed by the by-pointer capture fix earlier today).
@ __alloca_struct_params i syms i cg → v {
    : ~ s roster ( nurl_sym_get syms `__fn_params__` )
    ~ != 0 ( nurl_str_len roster ) {
        // Take one (name,type) pair: everything up to the next '|'.
        : i rlen ( nurl_str_len roster )
        : ~ i pi 0
        ~ & < pi rlen != ( nurl_str_get roster pi ) 124 { = pi + pi 1 }
        : s pair ( nurl_str_slice roster 0 pi )
        = roster ? < pi rlen ( nurl_str_slice roster + pi 1 - rlen - pi 1 ) ``
        // Split pair on '\t'.
        : i plen ( nurl_str_len pair )
        : ~ i ti 0
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
                    ( nurl_print ` = alloca ` ) ( nurl_print ( nurl_llty ptype ) ) ( nurl_print `\n` )
                    ( nurl_print `  store ` ) ( nurl_print ( nurl_llty ptype ) ) ( nurl_print ` %` )
                    ( nurl_print pname ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty ptype ) )
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
    : ~ i first 1
    : ~ i fidx 0
    ~ != ( nurl_lex_type lex ) TT_RBRACE {
        : s flt ( parse_type lex )
        // A field whose type is the struct itself BY VALUE makes the struct
        // infinitely sized (`: Node { i v  Node next }`). LLVM only rejects the
        // recursive value type later, at an `insertvalue` / `store` use site,
        // with a cryptic "operand and field disagree in type". Catch it at the
        // declaration with the canonical cure: box the field as a pointer.
        ? ( seq flt ( nurl_str_cat `%` sname ) )
        { ( die lex ( nurl_str_cat ( nurl_str_cat3
            `recursive struct '` sname `' has infinite size — a field holds the struct itself by value. Box it as a pointer: '* ` )
            ( nurl_str_cat sname `'` ) ) ) }
        {}
        ( check_type_known lex syms flt `a struct field type` )
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
            // The stored field type `flt` is the raw internal repr
            // (`u8`..`u64` distinct from the i-types since A1) — field
            // loads widen zext-vs-sext straight off it. Only the LLVM
            // struct BODY below needs the lowered spelling.
        }
        {}
        ? != first 0
        { ( nurl_print ( nurl_llty flt ) ) = first 0 }
        { ( nurl_print `, ` ) ( nurl_print ( nurl_llty flt ) ) }
        = fidx + fidx 1
    }
    ( nurl_lex_advance lex )
    ( nurl_print ` }\n\n` )
    ( nurl_sym_def syms sname ( nurl_str_cat `%` sname ) )
    ( nurl_sym_def syms ( nurl_str_cat sname `__is_type` ) `1` )
    ( nurl_sym_def syms ( nurl_str_cat sname `__field_count` ) ( nurl_str_int fidx ) )
}

// Narrow compile-time constant folding for integer-typed top-level
// consts. Lets `: i SECS * * 60 60 24` and `: i INT_MIN - -9223372036854775807 1`
// work where only a single literal was previously accepted. Pure prefix
// arithmetic over INT literals; no identifiers, no calls — fully
// transparent (it only computes a value, never hides control flow).
// `%` (TT_PERCENT) is deliberately excluded: at a top-level position
// `%` is the trait / impl / Drop decl sigil, which the lexical
// pre-passes dispatch on, so a `% a b` const value mis-scans. The other
// nine integer operators do not collide.
@ __is_const_int_op i tt → b {
    ? == tt TT_PLUS T
    ? == tt TT_MINUS T
    ? == tt TT_STAR T
    ? == tt TT_SLASH T
    ? == tt TT_AMP T
    ? == tt TT_PIPE T
    ? == tt TT_SHL T
    ? == tt TT_SHR T
    ? == tt TT_CARETCARET T
    F
}

// XOR via `(a|b) - (a&b)` so nurlc.nu itself stays `^^`-free (the
// stage-0 nurlc.py does not lex `^^`).
@ __const_int_apply i tt i a i b → i {
    ? == tt TT_PLUS { ^ + a b } {}
    ? == tt TT_MINUS { ^ - a b } {}
    ? == tt TT_STAR { ^ * a b } {}
    ? == tt TT_SLASH { ? == b 0 { ^ 0 } {} ^ / a b } {}
    ? == tt TT_AMP { ^ & a b } {}
    ? == tt TT_PIPE { ^ | a b } {}
    ? == tt TT_SHL { ^ << a b } {}
    ? == tt TT_SHR { ^ >> a b } {}
    ? == tt TT_CARETCARET { ^ - | a b & a b } {}
    ^ 0
}

// Recursive-descent evaluator for a prefix integer const expression.
// Consumes tokens; returns the folded i64.
@ const_eval_int i lex → i {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_INT {
        : i v ( nurl_lex_inum lex )
        ( nurl_lex_advance lex )
        ^ v
    } {}
    ? ( __is_const_int_op tt ) {
        ( nurl_lex_advance lex )
        : i a ( const_eval_int lex )
        : i b ( const_eval_int lex )
        ^ ( __const_int_apply tt a b )
    } {}
    ( die lex `const expression must be integer literals combined with + - * / << >> & | ^^ (use a precomputed literal for %)` )
    ^ 0
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
        ( rec_decl_loc syms cname ( nurl_lex_line lex ) lex )
        ( nurl_lex_advance lex )
        : i tt ( nurl_lex_type lex )
        ? == tt TT_INT
        { : i n ( nurl_lex_inum lex )
            ( nurl_lex_advance lex )
            ( nurl_print `@` ) ( nurl_print cname )
            ( nurl_print ` = global ` ) ( nurl_print ( nurl_llty lt ) ) ( nurl_print ` ` )
            // A bare integer initialiser is only valid for an integer-
            // typed global. A pointer global (`: s g 0`, `: *u buf 0`)
            // needs `null` / an `inttoptr` constant; an aggregate or
            // named-struct global (`: String g 0`, `: Point p 0`) needs
            // `zeroinitializer`.
            : i lt0 ( nurl_str_get lt 0 )
            ? == ( nurl_str_get lt - ( nurl_str_len lt ) 1 ) 42
            { ? == n 0
                { ( nurl_print `null` ) }
                { ( nurl_print `inttoptr (i64 ` ) ( nurl_print ( nurl_str_int n ) )
                    ( nurl_print ` to ` ) ( nurl_print ( nurl_llty lt ) ) ( nurl_print `)` ) } }
            { ? | | == lt0 37 == lt0 123 == lt0 91
                { ( nurl_print `zeroinitializer` ) }
                { ( nurl_print ( nurl_str_int n ) ) } }
            ( nurl_print `\n\n` )
            ( nurl_sym_def syms cname lt )
            ( nurl_sym_def syms ( nurl_str_cat cname `__global` ) `1` )
            // The const's signedness rides its stored type `lt` (raw
            // internal repr): `: u GU 200` records `u8`, and gen_ident's
            // load re-publishes it so `# i GU` widens with zext.
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
            // String globals are emitted as `global i8*` (writable storage),
            // so a `: ~ s g` must record the mutable flag like the i/f/b
            // branches above — without it, `= g …` was wrongly rejected as an
            // assignment to an immutable global (the grammar lists `s` as an
            // updatable mutable-global type).
            ? is_mutable
            { ( nurl_sym_def syms ( nurl_str_cat cname `__mutable` ) `1` ) }
            {}
        }
        // Integer const-expression RHS (operator-led): fold to a single
        // value at compile time. Gated on an integer LLVM type wider
        // than i1 so bool consts keep their dedicated branch above.
        ? & ( __is_const_int_op tt ) > ( int_width lt ) 1
        { : i n ( const_eval_int lex )
            ( nurl_print `@` ) ( nurl_print cname )
            ( nurl_print ` = global ` ) ( nurl_print ( nurl_llty lt ) ) ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n\n` )
            ( nurl_sym_def syms cname lt )
            ( nurl_sym_def syms ( nurl_str_cat cname `__global` ) `1` )
            ? is_mutable
            { ( nurl_sym_def syms ( nurl_str_cat cname `__mutable` ) `1` ) }
            {}
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
    // Host-imports mode (wasm): external FFI libs are resolved by the run-time
    // embedder as imports, not linked natively — skip the native sentinel gate.
    ? != g_ffi_host_imports 0 { ^ v } {}
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
            // Resolve the sentinel the SAME way as `$`-imports (__norm_import_path):
            // CWD-relative first — keeps the in-tree build / bootstrap byte-identical —
            // then $NURL_STDLIB, so an INSTALLED toolchain compiling from an arbitrary
            // directory (or a registry package) finds the shipped sentinel. A bare
            // CWD-relative check here meant a user building a compress.nu-importing
            // program outside the stdlib tree got a bogus "no build-time sentinel" error.
            ? == ( nurl_file_exists ( __norm_import_path sentinel ) ) 1 {} {
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
    // The C symbol name must be an identifier. A malformed header (`& "lib" @ @
    // foo`, a stray operator) otherwise took whatever token followed as the
    // name and emitted `declare T @<garbage>(…)` — IR only clang/llvm-as
    // rejected ("expected function name").
    ? ! ( is_ident_tok ( nurl_lex_type lex ) )
    { ( die lex `expected the C function name (an identifier) after '@' in an FFI declaration` ) }
    {}
    : s fname ( nurl_lex_val lex )
    // Lint: `&` externs belong to the declaring file's def roster so
    // an import used only for its FFI surface is not flagged unused.
    ( lint_note_def fname )
    ( nurl_lex_advance lex )
    : ~ s params_str ``
    // `;`-joined LLVM param types, consulted by gen_call to coerce each
    // argument to its declared FFI parameter width. Native LLVM silently
    // tolerates a width-mismatched call arg (e.g. an i64 integer literal
    // passed to an i32 parameter — high bits ignored in the ABI register),
    // but wasm is strict: the call's inferred function type then differs
    // from the import's declared type and wasm-ld replaces the callee with
    // an `unreachable` stub. Coercing at the call site fixes both targets.
    : ~ s ptypes ``
    : ~ i pct 0
    ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF {
        ? == ( nurl_lex_type lex ) TT_ELLIPSIS
        { ( nurl_lex_advance lex )  // consume '...'
            // Register variadic side-channel: the predicate flag and the
            // fixed-param count (decimal-stringified) drive the call-site
            // promotion path in gen_call.
            ( nurl_sym_def syms ( nurl_str_cat fname `__variadic` ) `1` )
            ( nurl_sym_def syms ( nurl_str_cat fname `__variadic_fixed` ) ( nurl_str_int pct ) )
            = params_str ? == pct 0 `...` ( nurl_str_cat params_str `, ...` )
            // Full param-type list incl. `...` — gen_call emits it as the
            // explicit callee function type (`call i32 (i8*, ...) @f`),
            // which LLVM requires for a correct variadic ABI.
            ( nurl_sym_def syms ( nurl_str_cat fname `__variadic_sig` ) params_str )
        }
        { : s lt ( parse_type lex )
            ( check_type_known lex syms lt `an FFI parameter type` )
            ? ( is_ident_tok ( nurl_lex_type lex ) ) { ( nurl_lex_advance lex ) } {}
            // params_str is IR text (the `declare` line + variadic call
            // sigs) — lowered; ptypes keeps the raw internal types so
            // the call-site width coercion sees signedness.
            ? == pct 0
            { = params_str ( nurl_llty lt ) = ptypes lt }
            { = params_str ( nurl_str_cat params_str ( nurl_str_cat `, ` ( nurl_llty lt ) ) )
                = ptypes ( nurl_str_cat3 ptypes `;` lt ) }
            = pct + pct 1
        }
    }
    ( expect lex TT_ARROW )
    : s ret_ty ( parse_type lex )
    ( check_type_known lex syms ret_ty `the FFI return type` )
    ( nurl_sym_def syms fname ret_ty )
    // Mark this name as a callable FFI symbol. gen_stmt's bare-ident-
    // as-statement check (critic v0.9.0 §1) uses this to die on
    // `name args` when the user meant `( name args )` — the @-fn
    // counterpart is detected via the `__src_file` entry written
    // by vis_record_fn, which FFI decls deliberately do not get
    // (FFI symbols are linker-level ABI globals, not NURL sources).
    ( nurl_sym_def syms ( nurl_str_cat fname `__ffi` ) `1` )
    // Per-parameter LLVM types for call-site width coercion (see `ptypes`).
    ( nurl_sym_def syms ( nurl_str_cat fname `__ffi_params` ) ptypes )
    // emit_header already emits `declare` lines for a small set of libc
    // symbols (malloc, free, puts, printf). If the user FFI-declares any of
    // those, re-emitting the same `declare` would trigger LLVM's "invalid
    // redefinition of function" error, so skip the emit — the symbol is
    // still registered above so callers resolve correctly.
    : b is_prelude_cfn | | | | ( seq fname `malloc` ) ( seq fname `free` ) ( seq fname `puts` ) ( seq fname `printf` ) ( seq fname `realpath` )
    // Dedupe `declare`s by symbol name across the whole compilation: two
    // imported modules may legitimately declare the same libc/runtime
    // extern (e.g. `nurl_rand_fill` in both std/random.nu and tls.nu), and
    // re-emitting an identical `declare` makes LLVM reject the module with
    // "invalid redefinition of function". The symbol is still registered
    // above (the `fname` / `__ffi` entries) so callers in every file
    // resolve correctly — only the duplicate IR line is suppressed. This
    // generalises the prelude-symbol skip.
    : s emitkey ( nurl_str_cat fname `__ffi_emitted` )
    : b already != 0 ( nurl_str_len ( nurl_sym_get syms emitkey ) )
    ? | is_prelude_cfn already
    {}
    { ( nurl_sym_def syms emitkey `1` )
        ( nurl_print `declare ` ) ( nurl_print ( nurl_llty ret_ty ) )
        ( nurl_print ` @` ) ( nurl_print fname )
        ( nurl_print `(` ) ( nurl_print params_str ) ( nurl_print `)\n\n` )
    }
}

// Check if current token could be a payload type (without consuming it)
@ could_be_payload_type i lex i syms → b {
    : i tt ( nurl_lex_type lex )
    ? | == tt TT_TYPE_KW | == tt TT_STAR | == tt TT_QUEST | == tt TT_QUESTQUEST | == tt TT_LBRACK | == tt TT_BANG == tt TT_LPAREN
    ^ T
    ? == tt TT_IDENT
    { : s maybe ( nurl_lex_val lex )
        : s entry ( nurl_sym_get syms maybe )
        ^ & != 0 ( nurl_str_len entry ) == ( nurl_str_get entry 0 ) 37
    }
    ^ F
}

// ── Auto-generated recursive Drop for boxed-payload enums ─────────────
//
// A variant payload that is a multi-field / non-pointer-f0 struct does
// not fit in the enum's 8-byte ptr slot, so gen_agg_lit heap-boxes it
// (nurl_alloc). Nothing reclaimed that box → leak. We generate a
// `drop__<E>` function that tag-dispatches and frees the box(es) of the
// active variant, and register it as the enum's `% Drop` impl so the
// existing auto-drop machinery (`:`-binding + void match-arm) fires it at
// scope exit. The box is compiler-managed memory that no manual code can
// reach, so freeing it here cannot double-free with user code.

// A payload type is "boxed" iff it is a named, non-pointer STRUCT whose
// field 0 is itself non-pointer (a single-pointer-handle struct such as
// String / Vec rides the slot directly; an enum payload is handled by
// its own drop; a `*`-suffixed pointer payload is not owned here).
@ __drop_is_boxed s pt i syms → b {
    : i n ( nurl_str_len pt )
    ? == 0 n { ^ F } {}
    ? != ( nurl_str_get pt 0 ) 37 { ^ F } {}
    ? == ( nurl_str_get pt - n 1 ) 42 { ^ F } {}
    : s sname ( nurl_str_slice pt 1 - n 1 )
    ? != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat sname `__variants` ) ) ) { ^ F } {}
    : s f0 ( nurl_sym_get syms ( nurl_str_cat3 sname `__idx_0` `__type` ) )
    ? == 0 ( nurl_str_len f0 ) { ^ F } {}
    ? == ( nurl_str_get f0 - ( nurl_str_len f0 ) 1 ) 42 { ^ F } {}
    ^ T
}

// True if variant `vname` has at least one boxed payload slot.
@ __drop_variant_has_box s vname i syms → b {
    : s pcs ( nurl_sym_get syms ( nurl_str_cat vname `__paycount` ) )
    : i pc ? != 0 ( nurl_str_len pcs ) ( nurl_str_to_int pcs ) 0
    : ~ i i 0
    : ~ b r F
    ~ < i pc {
        : s pt ( nurl_sym_get syms ( nurl_str_cat3 vname `__payload__` ( nurl_str_int i ) ) )
        ? ( __drop_is_boxed pt syms ) { = r T } {}
        = i + i 1
    }
    ^ r
}

// True if LLVM type `ty` is an enum that carries a compiler-auto Drop
// (`autodrop##%E` registered). Used by the borrow-provenance pass: a
// value of such a type can be EITHER owned or a borrow, and the
// `:`-binding auto-drop must skip the borrow case to avoid a double-free.
@ __is_autodrop_enum s ty i syms → b {
    ? == 0 ( nurl_str_len ty ) { ^ F } {}
    ? != ( nurl_str_get ty 0 ) 37 { ^ F } {}
    ? == ( nurl_str_get ty - ( nurl_str_len ty ) 1 ) 42 { ^ F } {}
    ^ != 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms ( nurl_str_cat `autodrop##` ty ) ) )
}

// Strip a leading `%` to form a drop-function name suffix.
@ __drop_mangle s ty → s {
    ? & != 0 ( nurl_str_len ty ) == ( nurl_str_get ty 0 ) 37
    { ^ ( nurl_str_slice ty 1 - ( nurl_str_len ty ) 1 ) } {}
    ^ ty
}

// `%Vec__<m>` → the element's LLVM type (via demangle).
@ __vec_elem_llvm s ty → s {
    ^ ( demangle_type ( nurl_str_slice ty 6 - ( nurl_str_len ty ) 6 ) )
}

// Fresh local register/label name (%d<n>) backed by a 1-slot counter.
@ __dr s ctr → s {
    : i n ( nurl_peek ctr 0 )
    ( nurl_poke ctr 0 + n 1 )
    ^ ( nurl_str_cat `%d` ( nurl_str_int n ) )
}

// Does an owned value of LLVM type `ty` need a drop? String / Vec own
// storage unconditionally; a named struct needs one iff a field does; a
// named enum iff a variant payload does. Vec/String short-circuit so the
// struct↔enum recursion is finite (value-nesting is acyclic).
@ __type_needs_drop s ty i syms → b {
    ? == 0 ( nurl_str_len ty ) { ^ F } {}
    ? ( seq ty `%String` ) { ^ T } {}
    ? != 0 ( nurl_str_starts ty `%Vec__` ) { ^ T } {}
    // A `%dyn.Trait` object owns its heap box (and, via the vtable, the boxed
    // value's own resources) — always droppable.
    ? != 0 ( nurl_str_starts ty `%dyn.` ) { ^ T } {}
    ? != ( nurl_str_get ty 0 ) 37 { ^ F } {}
    ? == ( nurl_str_get ty - ( nurl_str_len ty ) 1 ) 42 { ^ F } {}
    : s sname ( nurl_str_slice ty 1 - ( nurl_str_len ty ) 1 )
    : s vlist ( nurl_sym_get syms ( nurl_str_cat sname `__variants` ) )
    ? != 0 ( nurl_str_len vlist ) { ^ ( __enum_needs_drop vlist syms ) } {}
    : s fcs ( nurl_sym_get syms ( nurl_str_cat sname `__field_count` ) )
    : i fc ? != 0 ( nurl_str_len fcs ) ( nurl_str_to_int fcs ) 0
    : ~ i i 0
    : ~ b r F
    ~ < i fc {
        : s ft ( nurl_sym_get syms ( nurl_str_cat3 sname `__idx_` ( nurl_str_cat ( nurl_str_int i ) `__type` ) ) )
        ? ( __type_needs_drop ft syms ) { = r T } {}
        = i + i 1
    }
    ^ r
}

// One payload type owns a resource if it is String / Vec / a boxed
// struct / a wide (boxed) enum. (Narrow tag-only enum or scalar: no.)
@ __payload_needs_drop s pt i syms → b {
    ? == 0 ( nurl_str_len pt ) { ^ F } {}
    ? ( seq pt `%String` ) { ^ T } {}
    ? != 0 ( nurl_str_starts pt `%Vec__` ) { ^ T } {}
    ? ( __drop_is_boxed pt syms ) { ^ T } {}
    ? & == ( nurl_str_get pt 0 ) 37 != ( nurl_str_get pt - ( nurl_str_len pt ) 1 ) 42 {
        : s sn ( nurl_str_slice pt 1 - ( nurl_str_len pt ) 1 )
        ? != 0 ( nurl_str_len ( nurl_sym_get syms ( nurl_str_cat sn `__variants` ) ) ) {
            : s mp ( nurl_sym_get syms ( nurl_str_cat sn `__max_payloads` ) )
            ? & != 0 ( nurl_str_len mp ) > ( nurl_str_to_int mp ) 0 { ^ T } {}
        } {}
    } {}
    ^ F
}

@ __enum_needs_drop s variants i syms → b {
    : ~ s scan variants
    : ~ b r F
    ~ != 0 ( nurl_str_len scan ) {
        : s vname ( str_first_word scan )
        = scan ( str_skip_word scan )
        : s pcs ( nurl_sym_get syms ( nurl_str_cat vname `__paycount` ) )
        : i pc ? != 0 ( nurl_str_len pcs ) ( nurl_str_to_int pcs ) 0
        : ~ i i 0
        ~ < i pc {
            : s pt ( nurl_sym_get syms ( nurl_str_cat3 vname `__payload__` ( nurl_str_int i ) ) )
            ? ( __payload_needs_drop pt syms ) { = r T } {}
            = i + i 1
        }
    }
    ^ r
}

// Emit IR that drops an in-register value `valreg` of LLVM type `ty`.
// String / Vec reclaim their backing store via nurl_vec_drop (passing a
// drop_ptr thunk for owned elements); a struct / enum delegates to its
// generated drop__ function.
@ emit_drop_value s ty s valreg s ctr i syms → v {
    // Dynamic trait object: delegate to the synthesized `%dyn.<T>` destructor
    // (runs the vtable slot-0 drop on the boxed value, then frees the box).
    ? != 0 ( nurl_str_starts ty `%dyn.` ) {
        ( nurl_print `  call void @drop__` ) ( nurl_print ( nurl_str_slice ty 1 - ( nurl_str_len ty ) 1 ) )
        ( nurl_print `(` ) ( nurl_print ( nurl_llty ty ) ) ( nurl_print ` ` ) ( nurl_print valreg ) ( nurl_print `)\n` )
        ^ v
    } {}
    ? ( seq ty `%String` ) {
        : s c ( __dr ctr )
        ( nurl_print `  ` ) ( nurl_print c ) ( nurl_print ` = extractvalue %String ` ) ( nurl_print valreg ) ( nurl_print `, 0\n` )
        ( nurl_print `  call void @nurl_vec_drop(i8* ` ) ( nurl_print c ) ( nurl_print `, ptr null, i64 1)\n` )
        ^ v
    } {}
    ? != 0 ( nurl_str_starts ty `%Vec__` ) {
        : s c ( __dr ctr )
        ( nurl_print `  ` ) ( nurl_print c ) ( nurl_print ` = extractvalue ` ) ( nurl_print ( nurl_llty ty ) ) ( nurl_print ` ` ) ( nurl_print valreg ) ( nurl_print `, 0\n` )
        : s elem ( __vec_elem_llvm ty )
        ? ( __type_needs_drop elem syms ) {
            : s szp ( __dr ctr )
            ( nurl_print `  ` ) ( nurl_print szp ) ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `* null, i32 1\n` )
            : s szi ( __dr ctr )
            ( nurl_print `  ` ) ( nurl_print szi ) ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `* ` ) ( nurl_print szp ) ( nurl_print ` to i64\n` )
            ( nurl_print `  call void @nurl_vec_drop(i8* ` ) ( nurl_print c ) ( nurl_print `, ptr @drop_ptr__` ) ( nurl_print ( __drop_mangle elem ) ) ( nurl_print `, i64 ` ) ( nurl_print szi ) ( nurl_print `)\n` )
        } {
            ( nurl_print `  call void @nurl_vec_drop(i8* ` ) ( nurl_print c ) ( nurl_print `, ptr null, i64 1)\n` )
        }
        ^ v
    } {}
    ? & == ( nurl_str_get ty 0 ) 37 != ( nurl_str_get ty - ( nurl_str_len ty ) 1 ) 42 {
        ? ( __type_needs_drop ty syms ) {
            ( nurl_print `  call void @drop__` ) ( nurl_print ( __drop_mangle ty ) ) ( nurl_print `(` ) ( nurl_print ( nurl_llty ty ) ) ( nurl_print ` ` ) ( nurl_print valreg ) ( nurl_print `)\n` )
        } {}
        ^ v
    } {}
    ^ v
}

// `define void @drop_ptr__<m>(i8* %p)` — load an element through `%p`
// and drop it. Passed by value to nurl_vec_drop for owned Vec elements.
@ emit_drop_ptr_thunk s elem i syms → v {
    : s m ( __drop_mangle elem )
    : s ctr ( nurl_zalloc 8 )
    ( nurl_print `define void @drop_ptr__` ) ( nurl_print m ) ( nurl_print `(i8* %p) {\nentry:\n` )
    : s ep ( __dr ctr )
    ( nurl_print `  ` ) ( nurl_print ep ) ( nurl_print ` = bitcast i8* %p to ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `*\n` )
    : s ev ( __dr ctr )
    ( nurl_print `  ` ) ( nurl_print ev ) ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `* ` ) ( nurl_print ep ) ( nurl_print `\n` )
    ( emit_drop_value elem ev ctr syms )
    ( nurl_print `  ret void\n}\n` )
}

@ emit_drop_struct_fn s sname i syms → v {
    : s ctr ( nurl_zalloc 8 )
    ( nurl_print `define void @drop__` ) ( nurl_print sname )
    ( nurl_print `(%` ) ( nurl_print sname ) ( nurl_print ` %v) {\nentry:\n` )
    : s fcs ( nurl_sym_get syms ( nurl_str_cat sname `__field_count` ) )
    : i fc ? != 0 ( nurl_str_len fcs ) ( nurl_str_to_int fcs ) 0
    : ~ i i 0
    ~ < i fc {
        : s ft ( nurl_sym_get syms ( nurl_str_cat3 sname `__idx_` ( nurl_str_cat ( nurl_str_int i ) `__type` ) ) )
        ? ( __type_needs_drop ft syms ) {
            : s fr ( __dr ctr )
            ( nurl_print `  ` ) ( nurl_print fr ) ( nurl_print ` = extractvalue %` ) ( nurl_print sname ) ( nurl_print ` %v, ` ) ( nurl_print ( nurl_str_int i ) ) ( nurl_print `\n` )
            ( emit_drop_value ft fr ctr syms )
        } {}
        = i + i 1
    }
    ( nurl_print `  ret void\n}\n` )
}

// Drop one payload slot (enum field index `fidx`) of a known payload
// type. String / Vec slots hold the unwrapped handle (its f0); a boxed
// struct / wide-enum slot holds a heap-box pointer (load → drop → free).
@ emit_drop_enum_payload s ename s pt i fidx s ctr i syms → v {
    : s slot ( __dr ctr )
    ( nurl_print `  ` ) ( nurl_print slot ) ( nurl_print ` = extractvalue %` ) ( nurl_print ename ) ( nurl_print ` %v, ` ) ( nurl_print ( nurl_str_int fidx ) ) ( nurl_print `\n` )
    // The i64 slot holds a pointer (String/Vec f0, or a heap-box) —
    // materialise it once for every use below.
    : s sp ( __dr ctr )
    ( nurl_print `  ` ) ( nurl_print sp ) ( nurl_print ` = inttoptr i64 ` ) ( nurl_print slot ) ( nurl_print ` to i8*\n` )
    ? ( seq pt `%String` ) {
        ( nurl_print `  call void @nurl_vec_drop(i8* ` ) ( nurl_print sp ) ( nurl_print `, ptr null, i64 1)\n` )
        ^ v
    } {}
    ? != 0 ( nurl_str_starts pt `%Vec__` ) {
        : s elem ( __vec_elem_llvm pt )
        ? ( __type_needs_drop elem syms ) {
            : s szp ( __dr ctr )
            ( nurl_print `  ` ) ( nurl_print szp ) ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `* null, i32 1\n` )
            : s szi ( __dr ctr )
            ( nurl_print `  ` ) ( nurl_print szi ) ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty elem ) ) ( nurl_print `* ` ) ( nurl_print szp ) ( nurl_print ` to i64\n` )
            ( nurl_print `  call void @nurl_vec_drop(i8* ` ) ( nurl_print sp ) ( nurl_print `, ptr @drop_ptr__` ) ( nurl_print ( __drop_mangle elem ) ) ( nurl_print `, i64 ` ) ( nurl_print szi ) ( nurl_print `)\n` )
        } {
            ( nurl_print `  call void @nurl_vec_drop(i8* ` ) ( nurl_print sp ) ( nurl_print `, ptr null, i64 1)\n` )
        }
        ^ v
    } {}
    // boxed struct OR wide enum: load the payload through the box, drop
    // it recursively, free the box.
    : s bp ( __dr ctr )
    ( nurl_print `  ` ) ( nurl_print bp ) ( nurl_print ` = bitcast i8* ` ) ( nurl_print sp ) ( nurl_print ` to ` ) ( nurl_print ( nurl_llty pt ) ) ( nurl_print `*\n` )
    : s bv ( __dr ctr )
    ( nurl_print `  ` ) ( nurl_print bv ) ( nurl_print ` = load ` ) ( nurl_print ( nurl_llty pt ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty pt ) ) ( nurl_print `* ` ) ( nurl_print bp ) ( nurl_print `\n` )
    ( emit_drop_value pt bv ctr syms )
    ( nurl_print `  call void @nurl_free(i8* ` ) ( nurl_print sp ) ( nurl_print `)\n` )
}

@ emit_drop_enum_fn s ename s variants i syms → v {
    : s ctr ( nurl_zalloc 8 )
    ( nurl_print `define void @drop__` ) ( nurl_print ename )
    ( nurl_print `(%` ) ( nurl_print ename ) ( nurl_print ` %v) {\nentry:\n` )
    ( nurl_print `  %dtag = extractvalue %` ) ( nurl_print ename ) ( nurl_print ` %v, 0\n` )
    : ~ i vk 0
    : ~ s rest variants
    ~ != 0 ( nurl_str_len rest ) {
        : s vname ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s pcs ( nurl_sym_get syms ( nurl_str_cat vname `__paycount` ) )
        : i pc ? != 0 ( nurl_str_len pcs ) ( nurl_str_to_int pcs ) 0
        : ~ b vneed F
        : ~ i ci 0
        ~ < ci pc {
            : s pt ( nurl_sym_get syms ( nurl_str_cat3 vname `__payload__` ( nurl_str_int ci ) ) )
            ? ( __payload_needs_drop pt syms ) { = vneed T } {}
            = ci + ci 1
        }
        ? vneed {
            : s cmpr ( __dr ctr )
            : s ld ( nurl_str_cat `Ld` ( nurl_str_int vk ) )
            : s ln ( nurl_str_cat `Ln` ( nurl_str_int vk ) )
            ( nurl_print `  ` ) ( nurl_print cmpr ) ( nurl_print ` = icmp eq i64 %dtag, ` ) ( nurl_print ( nurl_str_int vk ) ) ( nurl_print `\n` )
            ( nurl_print `  br i1 ` ) ( nurl_print cmpr ) ( nurl_print `, label %` ) ( nurl_print ld ) ( nurl_print `, label %` ) ( nurl_print ln ) ( nurl_print `\n` )
            ( nurl_print ld ) ( nurl_print `:\n` )
            : ~ i pi 0
            ~ < pi pc {
                : s pt ( nurl_sym_get syms ( nurl_str_cat3 vname `__payload__` ( nurl_str_int pi ) ) )
                ? ( __payload_needs_drop pt syms ) {
                    ( emit_drop_enum_payload ename pt + pi 1 ctr syms )
                } {}
                = pi + pi 1
            }
            ( nurl_print `  br label %` ) ( nurl_print ln ) ( nurl_print `\n` )
            ( nurl_print ln ) ( nurl_print `:\n` )
        } {}
        = vk + vk 1
    }
    ( nurl_print `  ret void\n}\n` )
}

// Recursively emit the drop graph rooted at `ty` (dedup via dgen## keys
// in g_impl_name_syms). Marks `ty` done BEFORE recursing so self/mutual
// references (e.g. Xml ↔ XmlElem ↔ Vec Xml) terminate via forward refs.
@ gen_drop_for_type s ty i syms → v {
    ? ! ( __type_needs_drop ty syms ) { ^ v } {}
    : s mangle ( __drop_mangle ty )
    : s donekey ( nurl_str_cat `dgen##` mangle )
    ? != 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms donekey ) ) { ^ v } {}
    ( nurl_sym_def g_impl_name_syms donekey `1` )
    ? ( seq ty `%String` ) { ^ v } {}
    ? != 0 ( nurl_str_starts ty `%Vec__` ) {
        : s elem ( __vec_elem_llvm ty )
        ? ( __type_needs_drop elem syms ) {
            ( gen_drop_for_type elem syms )
            ( emit_drop_ptr_thunk elem syms )
        } {}
        ^ v
    } {}
    : s vlist ( nurl_sym_get syms ( nurl_str_cat mangle `__variants` ) )
    ? != 0 ( nurl_str_len vlist ) {
        : ~ s scan vlist
        ~ != 0 ( nurl_str_len scan ) {
            : s vname ( str_first_word scan )
            = scan ( str_skip_word scan )
            : s pcs ( nurl_sym_get syms ( nurl_str_cat vname `__paycount` ) )
            : i pc ? != 0 ( nurl_str_len pcs ) ( nurl_str_to_int pcs ) 0
            : ~ i i 0
            ~ < i pc {
                : s pt ( nurl_sym_get syms ( nurl_str_cat3 vname `__payload__` ( nurl_str_int i ) ) )
                ( gen_drop_for_type pt syms )
                = i + i 1
            }
        }
        ( emit_drop_enum_fn mangle vlist syms )
        ^ v
    } {}
    // struct: recurse field types, then emit
    : s fcs ( nurl_sym_get syms ( nurl_str_cat mangle `__field_count` ) )
    : i fc ? != 0 ( nurl_str_len fcs ) ( nurl_str_to_int fcs ) 0
    : ~ i i 0
    ~ < i fc {
        : s ft ( nurl_sym_get syms ( nurl_str_cat3 mangle `__idx_` ( nurl_str_cat ( nurl_str_int i ) `__type` ) ) )
        ( gen_drop_for_type ft syms )
        = i + i 1
    }
    ( emit_drop_struct_fn mangle syms )
}

// Entry: auto-drop is generated ONLY for enums that heap-box a payload
// (a multi-field / non-pointer-f0 struct) — the box is compiler-managed
// memory no user code can reach, so reclaiming it (and, recursively, the
// boxed struct's owned String/Vec/nested fields) cannot collide with the
// pervasive manual-free model. Enums whose payloads are all single
// handles (String, Vec) or scalars — Json, TomlValue, Result, Option,
// … — are deliberately EXCLUDED: they are managed by hand (json_free,
// …) and an auto-drop would double-free. Returns T (so the caller
// registers `drop##%E`) iff a drop graph was emitted.
@ emit_auto_drop s ename s variants i syms → b {
    : ~ b has_box F
    : ~ s scan variants
    ~ != 0 ( nurl_str_len scan ) {
        : s vname ( str_first_word scan )
        = scan ( str_skip_word scan )
        ? ( __drop_variant_has_box vname syms ) { = has_box T } {}
    }
    ? ! has_box { ^ F } {}
    ( gen_drop_for_type ( nurl_str_cat `%` ename ) syms )
    // Panic-unwind journal thunk for this autodrop enum (drop__<ename>
    // was just emitted; drop##%ename = ename is the registered mangle).
    ( emit_jdrop_thunk ( nurl_str_cat `%` ename ) ename )
    ^ T
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
    : ~ i tag 0
    : ~ i max_payloads 0
    : ~ s variants_str ``
    // Stop at '}' OR end-of-input. Without the EOF guard an unterminated enum
    // body (`: | E { A`, or a stray `//` comment eating the closing brace on a
    // single-line source) spun this loop forever: `nurl_lex_advance` is a
    // no-op at EOF, so the loop kept minting empty variants and never
    // progressed — nurlc hung instead of erroring. The trailing
    // `expect TT_RBRACE` then reports a clean "expected '}' but found end of
    // input" at the EOF. (Struct / match / block bodies already terminate
    // because their inner sub-parsers hit EOF first.)
    ~ & != ( nurl_lex_type lex ) TT_RBRACE != ( nurl_lex_type lex ) TT_EOF {
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
        : ~ i pcount 0
        ~ & != ( nurl_lex_type lex ) TT_RBRACE ( could_be_payload_type lex syms ) {
            : s pt ( parse_type lex )
            ( nurl_sym_def syms ( nurl_str_cat vname ( nurl_str_cat `__payload__` ( nurl_str_int pcount ) ) ) pt )
            // pt is the raw internal payload type — a `u`-family payload
            // stays unsigned end to end and the match binding widens
            // with zext off the type itself.
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

    // Generate LLVM type declaration: { i64, i64, i64, ... } with
    // max_payloads i64 slots. The slots are i64 — NOT ptr — because a
    // payload survives the slot round-trip only if the slot holds all 64
    // bits on every target: on wasm32 a ptr is 32 bits wide, so routing an
    // f64 bit-pattern (or a >2^32 int) through `inttoptr` silently
    // truncated it (the chaotic-showcase autodiff wasm miscompile).
    // Pointers ride the i64 slot via ptrtoint/inttoptr, which is lossless
    // on every supported target (wasm32 pointers zero-extend into i64).
    ( nurl_print `%` ) ( nurl_print ename )
    ( nurl_print ` = type { i64` )
    : ~ i pi 0
    ~ < pi max_payloads {
        ( nurl_print `, i64` )
        = pi + pi 1
    }
    ( nurl_print ` }\n` )

    // Register the enum type in symbol table
    ( nurl_sym_def syms ename ( nurl_str_cat `%` ename ) )
    ( nurl_sym_def syms ( nurl_str_cat ename `__is_type` ) `1` )

    // Auto-generate a recursive Drop that reclaims heap-boxed struct
    // payloads. Register it as the enum's `% Drop` impl so `:`-binding /
    // void match-arm auto-drop fires it — unless the user wrote their own.
    ? != 0 g_auto_drop_strings {
        : s dkey ( nurl_str_cat `drop##%` ename )
        ? == 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms dkey ) ) {
            ? ( emit_auto_drop ename variants_str syms )
            { ( nurl_sym_def g_impl_name_syms dkey ename )
                // Mark this as a COMPILER-auto drop (vs a user `% Drop`).
                // Auto drops fire only on owned `:`-bindings — never on a
                // match-arm payload, which is frequently a borrow (vec_get
                // returns an aliasing copy); dropping it would double-free
                // the container that still owns the value.
                ( nurl_sym_def g_impl_name_syms ( nurl_str_cat `autodrop##%` ename ) `1` ) }
            {}
        } {}
    } {}

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
    : ~ s result ``
    : i slen ( nurl_str_len src )
    : ~ i pos 0
    : ~ i word_start 0
    : ~ i in_string 0  // 1 while scanning inside a backtick-delimited string
    : ~ i in_comment 0  // 1 while scanning inside a // line comment
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
    // Lint: capture the `$` token's position before consuming it so
    // the unused-import warning points at the directive itself.
    : i __li_line ( nurl_lex_line lex )
    : i __li_col ( nurl_lex_col lex )
    ( nurl_lex_advance lex )  // consume '$'
    : s path ( __norm_import_path ( nurl_lex_val lex ) )
    ( lint_note_import path __li_line __li_col )
    ( nurl_lex_advance lex )  // consume path STR
    : ~ s alias ``
    ? ( is_ident_tok ( nurl_lex_type lex ) )
    { = alias ( nurl_lex_val lex )
        ( nurl_lex_advance lex )
    }
    {}

    : s __imp_key ( __canon_import_key path )
    ? ( mem_is_imported syms __imp_key )
    {}
    { ( mem_mark_imported syms __imp_key )
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
@ emit_one_instantiation s fname s mangled s type_args s caller_file s caller_line i syms i cg → v {
    : s tparams ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__tparams` ) )
    : s gsrc ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__gsrc` ) )
    // No stored template for this name: the call site referenced a
    // generic function whose defining file is not in the import
    // closure. Without this guard the empty source below re-lexes as
    // `@ <mangled> ` and dies with an opaque `expected '->' but found
    // end of input` pointing at synthetic `<generic …>:1` — useless
    // for finding the actual problem (a missing `$` import).
    ? == 0 ( nurl_str_len gsrc )
    { : s loc ? != 0 ( nurl_str_len caller_file )
        ( nurl_str_cat4 caller_file `:` caller_line `: ` )
        ``
        ( nurl_eprintln ( nurl_str_cat3 loc
        ( nurl_str_cat3 `error: call to generic function '` fname `' but no generic of that name is defined in this file or any '$'-imported file` )
        ` — add the '$' import for the file that defines it` ) )
        ( nurl_exit 1 )
    }
    {}
    : ~ s subst_src gsrc
    : ~ s tp_rest tparams
    : ~ s ta_rest type_args
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
    // Critic v0.9.0 §2: synthesise a filename that includes the call
    // site so any diagnostic emitted while re-parsing the substituted
    // body points the user at THEIR code, not the opaque `<generic>`.
    : s synth_name ? & != 0 ( nurl_str_len caller_file ) != 0 ( nurl_str_len caller_line )
    ( nurl_str_cat3 `<generic ` mangled
    ( nurl_str_cat4 ` from ` caller_file `:` ( nurl_str_cat caller_line `>` ) ) )
    ( nurl_str_cat3 `<generic ` mangled `>` )
    : i lex2 ( nurl_lex_new full_src synth_name )
    // DWARF Phase 7: stash the original generic-decl line so
    // gen_fn_decl_concrete points this mono's !DISubprogram at the
    // real source, not the synthetic `<generic>:1`. Cleared in a
    // `defer`-ish trailing assignment after the recursive call.
    : i saved_override g_dbg_override_line
    : s sl_s ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__src_line` ) )
    ? != 0 ( nurl_str_len sl_s )
    { = g_dbg_override_line ( nurl_str_to_int sl_s ) }
    {}
    // DWARF Phase 8 (critic A8): stash the template's DEFINING FILE
    // beside the line, so the mono's !DISubprogram carries a !DIFile
    // for the stdlib/template source instead of the top-level file.
    : s saved_override_file g_dbg_override_file
    : s sf_s ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__src_file` ) )
    ? != 0 ( nurl_str_len sf_s )
    { = g_dbg_override_file sf_s }
    {}
    // Mark this instantiation's concrete type-args so gen_member /
    // gen_field_store treat pointers to them as arrays (their generic
    // origin — opaque type variables — have no accessible fields). Saved
    // and restored because nested instantiations re-enter here.
    : s saved_mono_tys g_mono_tparam_tys
    = g_mono_tparam_tys type_args
    // Lint: re-parsing the substituted body records symbol uses; key
    // them to the template's defining file, not the top file (see
    // lint_note_used). Saved/restored around the recursive
    // gen_fn_decl because nested instantiations re-enter here.
    ? != g_lint 0
    { : s saved_uf ( nurl_sym_get g_lint_syms `use_file` )
        ( nurl_sym_def g_lint_syms `use_file`
        ( nurl_sym_get g_generic_syms ( nurl_str_cat fname `__src_file` ) ) )
        ( gen_fn_decl lex2 syms cg )
        ( nurl_sym_def g_lint_syms `use_file` saved_uf )
    }
    { ( gen_fn_decl lex2 syms cg ) }
    = g_dbg_override_line saved_override
    = g_dbg_override_file saved_override_file
    = g_mono_tparam_tys saved_mono_tys
}

// flush_deferred_instantiations: emit all queued generic instantiations.
// Re-reads count each iteration so transitive generics are also emitted.
@ flush_deferred_instantiations i syms i cg → v {
    : ~ i k 0
    ~ < k ( nurl_str_to_int ( nurl_sym_get g_generic_syms `__deferred_count__` ) ) {
        : s base ( nurl_str_cat `__def` ( nurl_str_int k ) )
        : s fname ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_fn` ) )
        : s mangled ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_mn` ) )
        : s type_args ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_ta` ) )
        : s caller_file ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_cf` ) )
        : s caller_line ( nurl_sym_get g_generic_syms ( nurl_str_cat base `_cl` ) )
        ( emit_one_instantiation fname mangled type_args caller_file caller_line syms cg )
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
    // libc string / parse primitives — declared here so the pure-NURL
    // `nurl_str_*` helpers can call them globally without per-file
    // `&`-FFI declarations. Returns mapped at their native C widths
    // (i32 for int-returners, i8* for ptr-returners); NURL callers do
    // their own widening via `# i` if they need i64.
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
    // libc stdio primitives — declared here so the pure-NURL
    // `nurl_file_*` helpers in stdlib/std/fs.nu can call them
    // globally.
    ( emit `declare i8*  @fopen(i8*, i8*)` )
    ( emit `declare i32  @fclose(i8*)` )
    ( emit `declare i32  @fputs(i8*, i8*)` )
    ( emit `declare i64  @fwrite(i8*, i64, i64, i8*)` )
    ( emit `declare i32  @fputc(i32, i8*)` )
    ( emit `declare i64  @fread(i8*, i64, i64, i8*)` )
    ( emit `declare i32  @feof(i8*)` )
    // fseek/ftell — POSIX stdio file-position primitives. Pure-NURL
    // file_size + future random-access I/O use these to learn the
    // file's length without going through `stat(2)` (whose `struct
    // stat` layout varies per platform). SEEK_END = 2 universally.
    ( emit `declare i32  @fseek(i8*, i64, i32)` )
    ( emit `declare i64  @ftell(i8*)` )
    // POSIX access(2) for the pure-NURL nurl_file_exists @-fn.
    ( emit `declare i32  @access(i8*, i32)` )
    // getenv(3) — import-path resolution consults $NURL_STDLIB so an
    // installed toolchain finds stdlib regardless of cwd (see
    // __norm_import_path).
    ( emit `declare i8*  @getenv(i8*)` )
    // realpath(3) — the import DEDUP key is the canonical path so the same
    // file reached through two symlink chains (diamond package deps:
    // deps/a/deps/gpu vs deps/gpu) compiles exactly once (see
    // __canon_import_key). Diagnostics keep the as-written path.
    ( emit `declare i8*  @realpath(i8*, i8*)` )
    ( emit `declare void @nurl_init(i32, i8**)` )
    ( emit `declare void @nurl_print(i8*)` )
    ( emit `declare void @nurl_eprint(i8*)` )
    ( emit `declare void @nurl_eprintln(i8*)` )
    ( emit `declare void @nurl_print_int(i64)` )
    ( emit `declare void @nurl_print_str(i8*)` )
    ( emit `declare void @nurl_print_bool(i1)` )
    ( emit `declare i64  @nurl_read_int()` )
    ( emit `declare i8*  @nurl_read_line()` )
    // nurl_read_n_bytes lives as pure NURL `read_n_bytes` in
    // `stdlib/core/io.nu`; it reads stdin via `nurl_stdin_read`
    // (declared by FFI in stdlib/core/posix.nu, no built-in declare).
    ( emit `declare i64  @nurl_stdin_eof()` )
    ( emit `declare void @nurl_flush_stdout()` )
    ( emit `declare void @nurl_flush_stderr()` )
    // nurl_str_get / _cat / _cat3 / _cat4 / _slice / _parse_int_range
    // / _parse_float_range are pure-NURL @-fns — no preamble declare
    // here to avoid clashing with their `define`s in user code and
    // the local copies inside nurlc.nu itself.  _str_int and
    // _str_float stay in C (printf-family %g, Grisu/Ryu TODO).
    ( emit `declare i8*  @nurl_str_int(i64)` )
    ( emit `declare i8*  @nurl_str_float(double)` )
    // nurl_str_len / _eq / _cmp / _to_int / _to_float / _starts /
    // _find / _ends / _memmem_range / _memcmp_lex are pure-NURL
    // @-fns (libc-thin wrappers calling strlen / strcmp / strncmp /
    // strstr / memcmp / memmem / atoll / atof directly via the global
    // preamble declarations emitted above).
    ( emit `declare i64    @nurl_scan_byte3(i8*, i64, i64, i64, i64)` )
    ( emit `declare i64    @nurl_byte_substr(i8*, i64, i8*, i64)` )
    ( emit `declare i64    @nurl_count_byte(i8*, i64, i64)` )
    ( emit `declare double @nurl_fast_atof(i8*, i64)` )
    // nurl_str_slice is a pure-NURL @-fn.
    // nurl_map_* (string→i64) is not part of the runtime — use the
    // generic `stdlib/std/hashmap.nu` HashMap[K V] at [s i] instead.
    ( emit `declare i8*  @nurl_read_file(i8*)` )
    ( emit `declare void @nurl_exit(i64)` )
    ( emit `declare i64  @nurl_argc()` )
    ( emit `declare i8*  @nurl_argv(i64)` )
    ( emit `declare i64  @nurl_argv_count()` )
    ( emit `declare i8*  @nurl_argv_get(i64)` )
    ( emit `declare i8*  @nurl_version()` )
    // nurl_lex_* are pure-NURL @-fns in compiler/nurlc.nu (see the
    // §6a Lexer block).
    ( emit `declare void @nurl_print_buf_start()` )
    ( emit `declare i8*  @nurl_print_buf_stop()` )
    ( emit `declare void @nurl_print_buf_reset()` )
    // nurl_lex_filename, nurl_sym_*, nurl_cg_*, nurl_get_last_type
    // and _set_last_type are pure-NURL @-fns (see top of this file).
    ( emit `declare i8*  @nurl_malloc(i64)` )
    ( emit `declare i8*  @nurl_alloc(i64)` )
    ( emit `declare i8*  @nurl_zalloc(i64)` )
    ( emit `declare i8*  @nurl_realloc(i8*, i64)` )
    ( emit `declare void @nurl_free(i8*)` )
    ( emit `declare void @nurl_journal_push(i8*)` )
    ( emit `declare void @nurl_journal_push_drop(i8*, ptr)` )
    ( emit `declare void @nurl_journal_forget(i8*)` )
    ( emit `declare void @nurl_memcpy(i8*, i8*, i64)` )
    ( emit `declare void @nurl_memmove(i8*, i8*, i64)` )
    ( emit `declare void @nurl_memset(i8*, i64, i64)` )
    ( emit `declare i64  @nurl_peek(i8*, i64)` )
    ( emit `declare void @nurl_poke(i8*, i64, i64)` )
    ( emit `declare void @nurl_vec_drop(i8*, ptr, i64)` )
    // nurl_file_* (open/write/write_range/write_byte/close/read_chunk
    // /eof/exists/del/dir_create/dir_remove) are pure-NURL @-fns in
    // stdlib/std/fs.nu, calling libc fopen/fputs/fwrite/fputc/fclose/
    // fread/feof/access/remove/mkdir/rmdir/fseek/ftell/open/mmap/
    // munmap directly.
    // nurl_errno_kind lives as `errno_kind` in `stdlib/core/posix.nu`.
    // libm wrappers and nurl_iabs / _ipow are pure-NURL (libm direct
    // FFI in stdlib/std/float.nu; iabs/ipow as plain @-fns in
    // stdlib/std/int.nu).
    ( emit `declare i64    @nurl_is_nan(double)` )
    ( emit `declare i64    @nurl_is_inf(double)` )
    ( emit `declare i64  @nurl_dir_list_open(i8*)` )
    ( emit `declare i8*  @nurl_dir_list_next(i64)` )
    ( emit `declare void @nurl_dir_list_close(i64)` )
    ( emit `declare i64  @nurl_http_perform_full(i8*, i8*, i8*, i8*)` )
    ( emit `declare i64  @nurl_http_perform_full_to(i8*, i8*, i8*, i8*, i64, i64)` )
    // The 7 accessors (status / err_kind / body / body_len /
    // header_count / header_name / header_value) are pure-NURL @-fns
    // in stdlib/ext/http.nu that read the NurlHttpResponse struct via
    // nurl_peek. Only the C-side freer stays — it walks the headers
    // array deallocating every name/value pair.
    ( emit `declare void @nurl_http_response_free(i64)` )
    ( emit `declare i64  @nurl_http_stream_open_to(i8*, i8*, i8*, i8*, i64, i64)` )
    ( emit `declare i8*  @nurl_http_stream_next(i64)` )
    ( emit `declare void @nurl_http_stream_close(i64)` )
    ( emit `declare i64  @nurl_http_stream_pump_headers(i64)` )
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
    // live in pure NURL under `stdlib/std/hash_*.nu`. Random surface
    // (`rand_u64` / `rand_hex_str`) is in `stdlib/std/random.nu`;
    // the OS-entropy bridge `nurl_rand_fill` is declared via
    // `& \`c\`` FFI directly there — no preamble declare here.
    // nurl_read_file_bytes / nurl_write_file_bytes / nurl_last_bytes_len
    // are pure NURL in `stdlib/std/fs.nu`; fread / fwrite write into
    // Vec[u]'s data buffer, vec_set_len records the count.
    ( emit `declare i64  @nurl_tcp_listen(i8*, i64, i64)` )
    ( emit `declare i64  @nurl_tcp_listen_tls(i8*, i64, i64, i8*, i8*)` )
    ( emit `declare i64  @nurl_tcp_listen_tls_alpn(i8*, i64, i64, i8*, i8*, i8*)` )
    ( emit `declare i8*  @nurl_tcp_alpn_selected(i64)` )
    ( emit `declare i64  @nurl_tcp_tls_add_sni(i64, i8*, i8*, i8*)` )
    ( emit `declare i64  @nurl_tcp_tls_reload(i64, i8*, i8*, i8*)` )
    ( emit `declare i64  @nurl_tcp_tls_require_client_cert(i64, i8*, i64)` )
    ( emit `declare i8*  @nurl_tcp_peer_cert_subject(i64)` )
    ( emit `declare i64  @nurl_tcp_accept(i64)` )
    ( emit `declare i64  @nurl_tcp_read(i64, i8*, i64)` )
    ( emit `declare i64  @nurl_tcp_write(i64, i8*, i64)` )
    ( emit `declare void @nurl_tcp_close(i64)` )
    ( emit `declare void @nurl_tcp_shutdown(i64)` )
    ( emit `declare i64  @nurl_tcp_err_kind(i64)` )
    ( emit `declare i8*  @nurl_tcp_peer_addr(i64)` )
    ( emit `declare void @nurl_tcp_set_timeout(i64, i64)` )
    // Thread / mutex / cond live in pure-NURL FFI in
    // stdlib/std/thread.nu — libpthread symbols (pthread_create /
    // mutex_* / cond_*) plus the tiny nurl_pthread_join_ptr /
    // _detach_ptr trampolines are declared on-demand in that module
    // via `& `c` @ ...`.
    ( emit `declare void @nurl_signal_install_shutdown(i64)` )
    ( emit `declare void @nurl_signal_trigger_shutdown()` )
    ( emit `declare void @nurl_panic(i8*)` )
    ( emit `declare i64  @nurl_recover(i8*, i8*)` )
    ( emit `declare i8*  @nurl_panic_last_msg()` )
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
// Directory portion of a file path (everything before the last '/'), or
// "" when the path has no '/' (i.e. it lives in the current directory).
@ __dirname s p → s {
    : i n ( nurl_str_len p )
    : ~ i i - n 1
    ~ >= i 0 {
        ? == ( nurl_str_get p i ) 47 { ^ ( nurl_str_slice p 0 i ) } {}
        = i - i 1
    }
    ^ ``
}

@ __norm_import_path s path → s {
    : ~ s cur path
    : ~ b done F
    ~ ! done {
        : i n ( nurl_str_len cur )
        ? & >= n 2 & == ( nurl_str_get cur 0 ) 46 == ( nurl_str_get cur 1 ) 47
        { = cur ( nurl_str_slice cur 2 - n 2 ) }
        { = done T }
    }
    // Importer-relative first: a path that exists next to the importing
    // file resolves to THAT file, regardless of cwd. This lets a multi-
    // file package reference its own modules (`$ `verify.nu``) and have
    // them resolve whether the package is built standalone, from the
    // monorepo root, or consumed as a `deps/<name>` dependency. stdlib /
    // deps / cwd-rooted paths don't exist beside the importer, so they
    // fall through to the cwd + $NURL_STDLIB lookup below — keeping the
    // bootstrap and existing imports byte-identical.
    : s sf ( vis_current_src_file )
    ? != # i sf 0 {
        : s dir ( __dirname sf )
        ? != 0 ( nurl_str_len dir ) {
            : s rel ( nurl_str_cat3 dir `/` cur )
            ? == ( nurl_file_exists rel ) 1 { ^ rel } {}
        } {}
    } {}
    // A cwd-relative hit wins next — this is the monorepo / in-tree
    // build, and keeps the bootstrap behaviour byte-identical (every
    // stdlib path resolves cwd-relative during self-host).
    ? == ( nurl_file_exists cur ) 1 { ^ cur } {}
    // Otherwise consult $NURL_STDLIB: an *installed* toolchain points it
    // at the prefix that contains `stdlib/`, so a program built from an
    // arbitrary directory (or a registry-installed package whose own
    // `$ `stdlib/...`` imports must resolve) finds the shipped stdlib
    // without vendoring it. No env / no hit → return cur unchanged and
    // let the normal "cannot read file" error fire.
    : s root ( getenv `NURL_STDLIB` )
    ? != # i root 0 {
        : s joined ( nurl_str_cat3 root `/` cur )
        ? == ( nurl_file_exists joined ) 1 { ^ joined } {}
    } {}
    ^ cur
}

// Canonical form of a RESOLVED import path, used ONLY as the dedup key in
// the seen-tables: the same file reached through different symlink chains
// (deps/tensor/deps/gpukit/deps/gpu vs deps/gpu — a diamond dependency)
// must compile exactly once or its symbols collide. realpath(3) resolves
// symlinks and '..'; on failure (races, exotic FS) fall back to the
// resolved path — same behaviour as before, just a weaker key. The
// as-written path stays in use for reading and diagnostics, so error
// messages and goldens are unchanged.
@ __canon_import_key s path → s {
    : s r ( realpath path # *u 0 )
    ? != # i r 0 { ^ r } {}
    ^ path
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
    // nurl_lex_val / _filename / _line_text / nurl_diag_caret /
    // nurl_cg_reg / _lbl / _get_last_type / nurl_sym_get are
    // pure-NURL @-fns; types come from the @-fn declarations.
    ( nurl_sym_def syms `nurl_argv` `i8*` )
    ( nurl_sym_def syms `nurl_argv_get` `i8*` )
    ( nurl_sym_def syms `nurl_version` `i8*` )
    ( nurl_sym_def syms `nurl_read_file` `i8*` )
    ( nurl_sym_def syms `nurl_read_line` `i8*` )
    // nurl_str_cat / _cat3 / _cat4 / _slice / _str_int are pure-NURL
    // @-fns. The sym_def keeps cross-module callers typed correctly
    // even when they don't `$`-import string.nu — omitting it makes
    // nurlc emit `call i64 @nurl_str_cat(...)` and the LLVM verifier
    // rejects the type mismatch. nurl_str_float still has a C body.
    ( nurl_sym_def syms `nurl_str_cat` `i8*` )
    ( nurl_sym_def syms `nurl_str_cat3` `i8*` )
    ( nurl_sym_def syms `nurl_str_cat4` `i8*` )
    ( nurl_sym_def syms `nurl_str_int` `i8*` )
    ( nurl_sym_def syms `nurl_str_float` `i8*` )
    ( nurl_sym_def syms `nurl_str_slice` `i8*` )
    // The four cat/slice helpers are PURE-NURL (defined in core/string.nu,
    // NOT in runtime.o) — unlike nurl_str_int / _float / read_* which have C
    // bodies and always link. The type pre-registration above keeps a
    // cross-module caller typed, but if NO file in the program imports
    // string.nu the symbol is undefined at link (clang: "use of undefined
    // value '@nurl_str_cat'"). Mark them so gen_call can name the missing
    // import at the call site instead. Safe: scan_fn_sigs is a COMPLETE
    // pre-pass over the whole program (it follows `$` imports), so a real
    // definition anywhere sets `<name>__arity` before any call is generated.
    ( nurl_sym_def syms `nurl_str_cat__needs_stdlib` `stdlib/core/string.nu` )
    ( nurl_sym_def syms `nurl_str_cat3__needs_stdlib` `stdlib/core/string.nu` )
    ( nurl_sym_def syms `nurl_str_cat4__needs_stdlib` `stdlib/core/string.nu` )
    ( nurl_sym_def syms `nurl_str_slice__needs_stdlib` `stdlib/core/string.nu` )
    // Mark allocating string runtime calls as returning OWNED str.
    // Gated on g_auto_drop_strings — off by default to keep the
    // compiler's own source compilable without false-positive
    // auto-drops. The sideband `__ret_owned` carries kind: "1" =
    // slice, "str" = string.
    ? != 0 g_auto_drop_strings
    { ( nurl_sym_def syms `nurl_str_cat__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_cat3__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_cat4__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_int__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_float__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_str_slice__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_read_file__ret_owned` `str` )
        ( nurl_sym_def syms `nurl_read_line__ret_owned` `str` )
    }
    {}
    ( nurl_sym_def syms `malloc` `i8*` )
    ( nurl_sym_def syms `nurl_malloc` `i8*` )
    ( nurl_sym_def syms `nurl_alloc` `i8*` )
    ( nurl_sym_def syms `nurl_zalloc` `i8*` )
    ( nurl_sym_def syms `nurl_realloc` `i8*` )
    // libc string / parse primitives
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
    // libc stdio — i64-typed returns align with how the @-fns
    // capture them. fopen returns FILE* (i8*); fread/fwrite return
    // size_t which we treat as i64.
    ( nurl_sym_def syms `fopen` `i8*` )
    ( nurl_sym_def syms `fclose` `i32` )
    ( nurl_sym_def syms `fputs` `i32` )
    ( nurl_sym_def syms `fwrite` `i64` )
    ( nurl_sym_def syms `fputc` `i32` )
    ( nurl_sym_def syms `fread` `i64` )
    ( nurl_sym_def syms `feof` `i32` )
    ( nurl_sym_def syms `fseek` `i32` )
    ( nurl_sym_def syms `ftell` `i64` )
    ( nurl_sym_def syms `access` `i32` )
    ( nurl_sym_def syms `getenv` `i8*` )
    ( nurl_sym_def syms `realpath` `i8*` )
    // file I/O
    ( nurl_sym_def syms `nurl_file_open` `i8*` )
    ( nurl_sym_def syms `nurl_file_write` `void` )
    ( nurl_sym_def syms `nurl_file_write_range` `void` )
    ( nurl_sym_def syms `nurl_file_write_byte` `void` )
    ( nurl_sym_def syms `nurl_file_close` `void` )
    ( nurl_sym_def syms `nurl_file_exists` `i64` )
    ( nurl_sym_def syms `nurl_file_del` `void` )
    // non-fatal fs API used by stdlib/std/fs.nu — raw is an i8* the caller
    // must `nurl_free` after copying (see read_file). Intentionally NOT
    // marked __ret_owned to avoid double-free against the manual free.
    // double-returning runtime functions
    // nurl_lex_fnum — pure-NURL @-fn (Phase 10).
    ( nurl_sym_def syms `nurl_parse_float_range` `double` )
    // libm wrappers + iabs/ipow live in `stdlib/std/float.nu` (libm
    // FFI) and `stdlib/std/int.nu` (pure-NURL int_abs / int_pow).
    // i64-returning math/parse helpers (still C-side)
    ( nurl_sym_def syms `nurl_is_nan` `i64` )
    ( nurl_sym_def syms `nurl_is_inf` `i64` )
    ( nurl_sym_def syms `nurl_parse_int_range` `i64` )
    // nurl_str_len / _eq / _cmp / _to_int / _to_float / _starts /
    // _find / _ends / _memmem_range / _memcmp_lex are pure-NURL
    // @-fns. Their return types are discovered from the @-fn
    // declaration itself.
    ( nurl_sym_def syms `nurl_scan_byte3` `i64` )
    ( nurl_sym_def syms `nurl_byte_substr` `i64` )
    ( nurl_sym_def syms `nurl_count_byte` `i64` )
    ( nurl_sym_def syms `nurl_fast_atof` `double` )
    // CLI tooling — i8*-returning calls return heap-owned strings (caller frees)
    ( nurl_sym_def syms `nurl_dir_list_next` `i8*` )
    ( nurl_sym_def syms `nurl_dir_list_open` `i64` )
    ( nurl_sym_def syms `nurl_dir_list_close` `void` )
    // HTTP runtime helpers (libcurl bridge — see runtime.c §14).
    // Body / header accessors return BORROWED i8* views into the
    // response struct, so they intentionally do NOT carry the
    // __ret_owned=str marker — the caller MUST NOT auto-free them.
    ( nurl_sym_def syms `nurl_http_perform_full` `i64` )
    ( nurl_sym_def syms `nurl_http_perform_full_to` `i64` )
    // accessors (status/err_kind/body/body_len/header_count/_name/
    // _value) are pure NURL in stdlib/ext/http.nu — see runtime.c
    // §14 + nurlc preamble note above.
    ( nurl_sym_def syms `nurl_http_response_free` `void` )
    // HTTP streaming (runtime.c §14b). Pull-based — NURL drives one
    // chunk at a time. `nurl_http_stream_next` returns a heap-owned
    // i8* (NULL on EOF/error); mark it as owned so auto-drop wraps it.
    ( nurl_sym_def syms `nurl_http_stream_open_to` `i64` )
    ( nurl_sym_def syms `nurl_http_stream_next` `i8*` )
    ( nurl_sym_def syms `nurl_http_stream_next__ret_owned` `str` )
    ( nurl_sym_def syms `nurl_http_stream_close` `void` )
    ( nurl_sym_def syms `nurl_http_stream_pump_headers` `i64` )
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
    // Crypto hash sym_defs live in their pure-NURL modules.
    // Binary file I/O lives as pure NURL in `stdlib/std/fs.nu`.
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
    ( nurl_sym_def syms `nurl_tcp_accept` `i64` )
    ( nurl_sym_def syms `nurl_tcp_read` `i64` )
    ( nurl_sym_def syms `nurl_tcp_write` `i64` )
    ( nurl_sym_def syms `nurl_tcp_close` `void` )
    ( nurl_sym_def syms `nurl_tcp_shutdown` `void` )
    ( nurl_sym_def syms `nurl_tcp_err_kind` `i64` )
    ( nurl_sym_def syms `nurl_tcp_peer_addr` `i8*` )
    ( nurl_sym_def syms `nurl_tcp_set_timeout` `void` )
    // Thread / mutex / cond live on the pure-NURL FFI side:
    // pthread_create / pthread_mutex_* / pthread_cond_* plus the
    // nurl_pthread_join_ptr / _detach_ptr trampolines are declared
    // in stdlib/std/thread.nu via `& `c` @ ...`, so no sym_def
    // registrations are needed here.
    ( nurl_sym_def syms `nurl_signal_install_shutdown` `void` )
    ( nurl_sym_def syms `nurl_signal_trigger_shutdown` `void` )
    ( nurl_sym_def syms `nurl_panic` `void` )
    ( nurl_sym_def syms `nurl_recover` `i64` )
    ( nurl_sym_def syms `nurl_panic_last_msg` `i8*` )
    // void runtime functions
    ( nurl_sym_def syms `nurl_print` `void` )
    ( nurl_sym_def syms `nurl_eprint` `void` )
    ( nurl_sym_def syms `nurl_eprintln` `void` )
    ( nurl_sym_def syms `nurl_print_int` `void` )
    ( nurl_sym_def syms `nurl_print_str` `void` )
    ( nurl_sym_def syms `nurl_print_bool` `void` )
    // nurl_lex_advance, nurl_sym_def / _push / _pop, nurl_cg_reset
    // and nurl_set_last_type are pure-NURL @-fns; their types come
    // from the @-fn declarations.
    ( nurl_sym_def syms `nurl_exit` `void` )
    ( nurl_sym_def syms `nurl_flush_stdout` `void` )
    ( nurl_sym_def syms `nurl_flush_stderr` `void` )
    ( nurl_sym_def syms `nurl_stdin_eof` `i64` )
    ( nurl_sym_def syms `free` `void` )
    ( nurl_sym_def syms `nurl_free` `void` )
    // nurl_map_* lives as the generic HashMap[K V] — see emit_preamble.
    ( nurl_sym_def syms `nurl_memcpy` `void` )
    ( nurl_sym_def syms `nurl_memmove` `void` )
    ( nurl_sym_def syms `nurl_poke` `void` )
    // output buffering
    ( nurl_sym_def syms `nurl_print_buf_start` `void` )
    ( nurl_sym_def syms `nurl_print_buf_stop` `i8*` )
    ( nurl_sym_def syms `nurl_print_buf_reset` `void` )
    // lexer position save/restore
    // nurl_lex_cur_start / _src_slice / _set_pos — pure-NURL @-fns (Phase 10).
    // Header-declared builtins that were MISSING from this table.
    // They compiled anyway only via gen_call's silent i64 default —
    // correct for the i64-returning ones by luck, invalid IR for the
    // rest. The unknown-callee diagnostic (gen_call) now rejects any
    // unregistered name, so this table must cover every `declare` that
    // emit_header writes. Keep the two in sync.
    ( nurl_sym_def syms `nurl_peek` `i64` )
    ( nurl_sym_def syms `nurl_init` `void` )
    ( nurl_sym_def syms `nurl_memset` `void` )
    ( nurl_sym_def syms `nurl_vec_drop` `void` )
    ( nurl_sym_def syms `nurl_argc` `i64` )
    ( nurl_sym_def syms `nurl_argv_count` `i64` )
    ( nurl_sym_def syms `nurl_read_int` `i64` )
    ( nurl_sym_def syms `puts` `i32` )
    ( nurl_sym_def syms `printf` `i32` )
    ( nurl_sym_def syms `printf__variadic` `1` )
    ( nurl_sym_def syms `printf__variadic_fixed` `1` )
    ( nurl_sym_def syms `printf__variadic_sig` `i8*, ...` )
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
        : ~ i depth 1
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
    // Lint: the trait and its method names are decls of this file —
    // an import supplying only a trait must not be flagged unused
    // when a consumer impls it / calls its methods.
    ( lint_note_def tname )
    ( expect lex TT_LBRACE )
    // EOF guards on both loops: an unterminated trait body (`% T {`, or a
    // method header with no following `{`/`@`/`}` at EOF) otherwise spins on
    // no-op `nurl_lex_advance` forever — nurlc hung instead of erroring.
    ~ & != ( nurl_lex_type lex ) TT_RBRACE != ( nurl_lex_type lex ) TT_EOF {
        // Associated-type declaration `type Name` — a per-impl type the trait's
        // methods may name. Record the name; each impl must bind it.
        ? & == ( nurl_lex_type lex ) TT_IDENT ( seq ( nurl_lex_val lex ) `type` )
        { ( nurl_lex_advance lex )  // skip 'type'
            ? ! ( is_ident_tok ( nurl_lex_type lex ) )
            { ( die lex `'type' in a trait body must be followed by an associated-type name` ) }
            {}
            : s aname ( nurl_lex_val lex )
            ( nurl_lex_advance lex )  // consume the associated-type name
            : s akey ( nurl_str_cat tname `__assoc` )
            : s acur ( nurl_sym_get g_trait_syms akey )
            // Idempotent append (same double-scan reason as __defaults).
            ? ! ( str_contains_word acur aname )
            { ( nurl_sym_def g_trait_syms akey
                ? == 0 ( nurl_str_len acur ) aname ( nurl_str_cat acur ( nurl_str_cat ` ` aname ) ) ) }
            {}
        }
        { ? == ( nurl_lex_type lex ) TT_AT
            { ( nurl_lex_advance lex )  // skip '@'
                ? ( is_ident_tok ( nurl_lex_type lex ) )
                { : s mname ( nurl_lex_val lex )
                    ( lint_note_def mname )
                    ( nurl_lex_advance lex )  // consume method name
                    : i sig_start ( nurl_lex_cur_start lex )
                    // Skip params / → / ret_ty until we hit '{' (body), next '@',
                    // or '}' (end of trait).
                    ~ & & & != ( nurl_lex_type lex ) TT_LBRACE
                    != ( nurl_lex_type lex ) TT_AT
                    != ( nurl_lex_type lex ) TT_RBRACE
                    != ( nurl_lex_type lex ) TT_EOF {
                        ( nurl_lex_advance lex )
                    }
                    // Dynamic-dispatch seam (docs/spec.md §4.9): record the trait's
                    // method set in declaration order plus each method's signature
                    // ("params → ret") — the vtable layout a future `dyn Trait` would
                    // index. The static dispatch path never reads it; it materialises
                    // the data so the extension is a localised addition, not a rescan.
                    // Required AND default methods, idempotent (twice-scanned imports).
                    : i msig_end ( nurl_lex_cur_start lex )
                    : s msig ( nurl_lex_src_slice lex sig_start - msig_end sig_start )
                    ( nurl_sym_def g_trait_syms
                    ( nurl_str_cat tname ( nurl_str_cat `__` ( nurl_str_cat mname `__sig` ) ) ) msig )
                    : s methods_key ( nurl_str_cat tname `__methods` )
                    : s mcur ( nurl_sym_get g_trait_syms methods_key )
                    ? ! ( str_contains_word mcur mname )
                    { ( nurl_sym_def g_trait_syms methods_key
                        ? == 0 ( nurl_str_len mcur ) mname ( nurl_str_cat mcur ( nurl_str_cat ` ` mname ) ) ) }
                    {}
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
                        // Idempotent append: a `$`-imported trait body is scanned
                        // twice (driver scan_fn_sigs + gen_import_decl's re-scan), so
                        // re-adding the same method must not grow the list — else
                        // emit_missing_defaults emits the default twice → an LLVM
                        // "invalid redefinition". (The __src store above is a plain
                        // overwrite, already idempotent.)
                        ? ! ( str_contains_word cur mname )
                        { ( nurl_sym_def g_trait_syms defaults_key
                            ? == 0 ( nurl_str_len cur )
                            mname
                            ( nurl_str_cat cur ( nurl_str_cat ` ` mname ) ) ) }
                        {}
                    }
                    {}  // header only — required method, no template to store
                }
                { ( nurl_lex_advance lex ) }
            }
            { ( nurl_lex_advance lex ) } }
    }
    ( expect lex TT_RBRACE )  // consume '}' — clean error if unterminated at EOF
}

// trait_default_ret: given a default method's substituted source
// "params → ret { body }", return the ret type as an LLVM type string.
@ trait_default_ret s subst_src → s {
    : i lex2 ( nurl_lex_new subst_src `<trait_default_ret>` )
    ~ & != ( nurl_lex_type lex2 ) TT_ARROW != ( nurl_lex_type lex2 ) TT_EOF {
        ( nurl_lex_advance lex2 )
    }
    : ~ s ret `i64`
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
@ register_missing_defaults i lex s tname s impl_nurl s impl_llvm s impl_mangle s provided s bindings i syms → v {
    : s tparam ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__tparam` ) )
    : ~ s defaults ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__defaults` ) )
    ~ != 0 ( nurl_str_len defaults ) {
        : s mname ( str_first_word defaults )
        = defaults ( str_skip_word defaults )
        ? ( str_contains_word provided mname )
        {}  // explicitly overridden by impl
        { : s src ( nurl_sym_get g_trait_syms
            ( nurl_str_cat tname ( nurl_str_cat `__` ( nurl_str_cat mname `__src` ) ) ) )
            : s subst0 ? != 0 ( nurl_str_len tparam )
            ( subst_source_raw src tparam impl_nurl )
            src
            // Substitute the trait's associated types to this impl's bindings,
            // so a default that returns/uses one lowers to the impl's choice.
            : s subst ( subst_assoc subst0 bindings )
            : s ret_ty ( trait_default_ret subst )
            : s key ( nurl_str_cat mname ( nurl_str_cat `##` impl_llvm ) )
            ( __coherence_register lex mname impl_llvm impl_nurl tname )
            ( nurl_sym_def g_impl_ret_syms key ret_ty )
            ( nurl_sym_def g_impl_name_syms key impl_mangle )
            // Mark the bare method name as impl-backed so gen_call's
            // unknown-callee check lets it through to impl dispatch.
            ( nurl_sym_def g_impl_name_syms ( nurl_str_cat mname `__impl_seen` ) `1` )
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

// __parse_assoc_binding: at a `type Name Concrete` line inside an IMPL body
// (lexer on the `type` keyword), consume all three tokens and return the
// "Name Concrete" pair (Concrete a single simple NURL type name). Used by both
// the scan and the IR-emit passes to collect an impl's associated-type
// bindings. A compound binding type (`* T`, `Vec T`) is rejected — the same
// simple-type restriction trait-default substitution already carries.
@ __parse_assoc_binding i lex → s {
    ( nurl_lex_advance lex )  // skip 'type'
    ? ! ( is_ident_tok ( nurl_lex_type lex ) )
    { ( die lex `'type' in an impl body must be followed by an associated-type name` ) }
    {}
    : s aname ( nurl_lex_val lex )
    ( nurl_lex_advance lex )  // consume the name
    : s aval ( capture_impl_nurl_name lex )
    ? == 0 ( nurl_str_len aval )
    { ( die lex ( nurl_str_cat3 `associated type '` aname `' must be bound to a simple type name` ) ) }
    {}
    ( nurl_lex_advance lex )  // consume the bound type
    ^ ( nurl_str_cat aname ( nurl_str_cat ` ` aval ) )
}

// scan_impl_decl: pre-scan a % trait/impl declaration, registering impl methods.
// Registers in g_impl_ret_syms and g_impl_name_syms so gen_call can dispatch.
// Coherence guard for trait-method dispatch. Each (method, LLVM-type) pair may
// be registered by exactly ONE impl. A second registration is either a
// duplicate impl of the same trait, or two different traits sharing a method
// name for one type — both ambiguous for NURL's bare-name dispatch. Type
// aliases that share an LLVM lowering (i / i64, u / u8, f / f64) collide here
// and are reported as duplicate impls rather than reaching LLVM as a function
// redefinition. Call BEFORE the g_impl_name_syms registration; it records the
// owning trait so a later collision's diagnostic can name both traits.
@ __coherence_register i lex s mname s impl_llvm s impl_nurl s tname → v {
    : s key ( nurl_str_cat mname ( nurl_str_cat `##` impl_llvm ) )
    : s pos ( nurl_str_cat ( nurl_lex_filename lex )
    ( nurl_str_cat `:` ( nurl_str_int ( nurl_lex_line lex ) ) ) )
    : s prior ( nurl_sym_get g_impl_name_syms key )
    ? != 0 ( nurl_str_len prior ) {
        : s prior_pos ( nurl_sym_get g_impl_pos_syms key )
        ? ( seq prior_pos pos )
        {}  // same source location → idempotent re-scan of the same impl
        {  // a different location → a genuine duplicate or cross-trait clash
            : s pt ( nurl_sym_get g_impl_trait_syms key )
            : s ty ? != 0 ( nurl_str_len impl_nurl ) impl_nurl impl_llvm
            ? ( seq pt tname )
            { ( die lex ( nurl_str_cat
                ( nurl_str_cat3 `duplicate impl of trait '` tname `' for type '` )
                ( nurl_str_cat ( nurl_str_cat3 ty `' (method '` mname ) `') — each trait may be implemented once per type` ) ) ) }
            { ( die lex ( nurl_str_cat
                ( nurl_str_cat3 `method '` mname `' for type '` )
                ( nurl_str_cat ( nurl_str_cat3 ty `' is provided by both trait '` pt )
                ( nurl_str_cat3 `' and trait '` tname `' — bare-name dispatch cannot disambiguate` ) ) ) ) }
        }
    } {}
    ( nurl_sym_def g_impl_trait_syms key tname )
    ( nurl_sym_def g_impl_pos_syms key pos )
}

// For trait_decl: stores default-method templates in g_trait_syms.
// For impl_decl: after scanning explicit methods, fills in dispatch entries
// for any of the trait's defaults that the impl did not override.
@ scan_impl_decl i lex i syms → v {
    ( nurl_lex_advance lex )  // skip '%'
    : s tname ( nurl_lex_val lex )
    ( nurl_lex_advance lex )  // skip trait name
    // Capture optional type param [T]  (bare letter T lexes as TT_BOOL)
    : ~ s tparam ``
    ? == ( nurl_lex_type lex ) TT_LBRACK
    { ( nurl_lex_advance lex )
        : i tpt ( nurl_lex_type lex )
        ? | ( is_ident_tok tpt ) == tpt TT_BOOL
        { = tparam ( nurl_lex_val lex ) }
        {}
        ~ & != ( nurl_lex_type lex ) TT_RBRACK != ( nurl_lex_type lex ) TT_EOF { ( nurl_lex_advance lex ) }
        ( expect lex TT_RBRACK )  // ']'
    }
    {}
    // Optional supertrait clause `% Sub : Super…` — a ':' here (never legal
    // before a trait body or an impl type) introduces one or more supertrait
    // names, read until the body's '{'. Implies: any type implementing Sub
    // must also implement each Super (enforced after scan_fn_sigs).
    : ~ s supers ``
    ? == ( nurl_lex_type lex ) TT_COLON
    { ( nurl_lex_advance lex )  // skip ':'
        // Supertrait names are user-defined trait identifiers (TT_IDENT) — never
        // a built-in type keyword. Stopping at non-IDENT means `% A : B i {` (a
        // bogus supertrait clause on an impl) leaves `i` for the impl path,
        // whose guard rejects it, rather than silently eating the impl type.
        ~ & == ( nurl_lex_type lex ) TT_IDENT != ( nurl_lex_type lex ) TT_EOF {
            = supers ? == 0 ( nurl_str_len supers )
            ( nurl_lex_val lex )
            ( nurl_str_cat supers ( nurl_str_cat ` ` ( nurl_lex_val lex ) ) )
            ( nurl_lex_advance lex )
        }
        ? == 0 ( nurl_str_len supers )
        { ( die lex `supertrait clause ':' must be followed by at least one trait name` ) }
        {}
    }
    {}
    // Disambiguate: '{' → trait_decl, else → impl_decl
    ? == ( nurl_lex_type lex ) TT_LBRACE
    {  // trait: remember its type param and scan for default methods
        ( nurl_sym_def g_trait_syms ( nurl_str_cat tname `__tparam` ) tparam )
        ( nurl_sym_def g_trait_syms ( nurl_str_cat tname `__istrait` ) `1` )
        ? != 0 ( nurl_str_len supers )
        { ( nurl_sym_def g_trait_syms ( nurl_str_cat tname `__supers` ) supers ) }
        {}
        ( scan_trait_body lex tname )
    }
    {  // impl_decl: read implementing type, then scan methods
        ? != 0 ( nurl_str_len supers )
        { ( die lex `':' supertrait clause is only valid on a trait declaration, not an impl` ) }
        {}
        : s impl_nurl ( capture_impl_nurl_name lex )
        : s impl_llvm ( parse_type lex )  // e.g. "i64", "i8*", "%Point"
        : s impl_mangle ( mangle_type impl_llvm )
        // Record that `tname` is implemented for this LLVM type, so a
        // generic bound `A: tname` can be verified at instantiation.
        ( nurl_sym_def g_trait_syms ( nurl_str_cat3 tname `##` impl_llvm ) `1` )
        // Park a supertrait obligation: after every impl in the program is
        // registered, each supertrait of `tname` must also be implemented for
        // this type. Recorded unconditionally (the trait's supers may not be
        // parsed yet); the deferred pass skips impls whose trait has none.
        : s spos ( nurl_str_cat ( nurl_lex_filename lex )
        ( nurl_str_cat `:` ( nurl_str_int ( nurl_lex_line lex ) ) ) )
        // Four space-separated fields per record (none contains a space):
        // "<Sub> <impl_llvm> <nurl_type> <file:line> ".
        = g_super_obligations ( nurl_str_cat g_super_obligations
        ( nurl_str_cat tname ( nurl_str_cat ` `
        ( nurl_str_cat impl_llvm ( nurl_str_cat ` `
        ( nurl_str_cat impl_nurl ( nurl_str_cat ` `
        ( nurl_str_cat spos ` ` ) ) ) ) ) ) ) )
        ( expect lex TT_LBRACE )
        : ~ s provided ``
        : ~ s bindings ``  // "name val …" associated-type bindings of this impl
        ~ & != ( nurl_lex_type lex ) TT_RBRACE != ( nurl_lex_type lex ) TT_EOF {
            ? & == ( nurl_lex_type lex ) TT_IDENT ( seq ( nurl_lex_val lex ) `type` )
            { : s pair ( __parse_assoc_binding lex )
                = bindings ? == 0 ( nurl_str_len bindings )
                pair ( nurl_str_cat bindings ( nurl_str_cat ` ` pair ) ) }
            { ? == ( nurl_lex_type lex ) TT_AT
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
                            ( __coherence_register lex mname impl_llvm impl_nurl tname )
                            ( nurl_sym_def g_impl_ret_syms key ret_ty )
                            ( nurl_sym_def g_impl_name_syms key impl_mangle )
                            // Mark the bare method name as impl-backed so
                            // gen_call's unknown-callee check lets it
                            // through to impl dispatch.
                            ( nurl_sym_def g_impl_name_syms ( nurl_str_cat mname `__impl_seen` ) `1` )
                            : s mangled ( nurl_str_cat mname ( nurl_str_cat `__` impl_mangle ) )
                            ( nurl_sym_def syms mangled ret_ty )
                        }
                        {}
                        ( skip_balanced lex )  // skip method body
                    }
                    { ( nurl_lex_advance lex ) }
                }
                { ( nurl_lex_advance lex ) } }
        }
        ( expect lex TT_RBRACE )  // consume '}' — clean error if unterminated at EOF
        // Associated-type coherence: the impl must bind exactly the trait's
        // declared associated types — every one, and no unknown name. (The
        // trait, like its defaults, must be scanned before the impl for its
        // __assoc list to be visible; the substitution below relies on it too.)
        ( verify_assoc_bindings lex tname impl_nurl bindings )
        // After the impl's explicit methods, synthesize dispatch entries for
        // any of the trait's defaults that this impl did not override, with the
        // trait's associated types substituted to this impl's bindings.
        ? != 0 ( nurl_str_len impl_nurl )
        { ( register_missing_defaults lex tname impl_nurl impl_llvm impl_mangle provided bindings syms ) }
        {}
    }
}

// verify_assoc_bindings: associated-type coherence for one impl block. Every
// associated type the trait declares must be bound by the impl, and every
// `type` line in the impl must name a declared associated type — so an impl is
// total over the trait's associated types and a typo'd binding is rejected at
// its definition rather than surfacing as an unsubstituted name in LLVM IR.
@ verify_assoc_bindings i lex s tname s impl_nurl s bindings → v {
    : s declared ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__assoc` ) )
    // (a) every binding names a declared associated type — checked first so a
    // typo'd `type Elment i` is reported as the unknown name, not as the (also
    // true, but less precise) "Elem unbound".
    : ~ s brest bindings
    ~ != 0 ( nurl_str_len brest ) {
        : s bn ( str_first_word brest )
        = brest ( str_skip_word brest )
        = brest ( str_skip_word brest )  // skip the bound value
        ? ! ( str_contains_word declared bn )
        { ( die lex ( nurl_str_cat
            ( nurl_str_cat3 `trait '` tname `' has no associated type '` )
            ( nurl_str_cat3 bn `' to bind for type '` ( nurl_str_cat impl_nurl `'` ) ) ) ) }
        {}
    }
    // (b) every declared associated type is bound
    : ~ s drest declared
    ~ != 0 ( nurl_str_len drest ) {
        : s an ( str_first_word drest )
        = drest ( str_skip_word drest )
        ? == 0 ( nurl_str_len ( __assoc_val bindings an ) )
        { ( die lex ( nurl_str_cat
            ( nurl_str_cat3 `impl of trait '` tname `' for type '` )
            ( nurl_str_cat ( nurl_str_cat3 impl_nurl `' must bind associated type '` an )
            `' (add a 'type' line)` ) ) ) }
        {}
    }
}

// verify_super_obligations: the supertrait soundness sweep. Runs once, after
// scan_fn_sigs has registered every impl in the program (the main file and all
// `$`-imports), so it sees the full set of (trait, type) impls regardless of
// declaration or import order. For each impl block parked in
// g_super_obligations, look up its trait's supertraits and require each one to
// be implemented for the SAME type — the static guarantee that backs `T: Sub ⇒
// T: Super`, so a bound `[A: Sub]` may freely call any supertrait method on A
// (dispatch resolves through the supertrait impl that this check proves exists).
@ verify_super_obligations → v {
    : ~ s rest g_super_obligations
    ~ != 0 ( nurl_str_len rest ) {
        : s sub ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s llvm ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s nty ( str_first_word rest )
        = rest ( str_skip_word rest )
        : s pos ( str_first_word rest )
        = rest ( str_skip_word rest )
        // Each supertrait of `sub` must be implemented for `llvm`.
        : ~ s sup_rest ( nurl_sym_get g_trait_syms ( nurl_str_cat sub `__supers` ) )
        ~ != 0 ( nurl_str_len sup_rest ) {
            : s sup ( str_first_word sup_rest )
            = sup_rest ( str_skip_word sup_rest )
            ? == 0 ( nurl_str_len ( nurl_sym_get g_trait_syms
            ( nurl_str_cat3 sup `##` llvm ) ) )
            { ( die_at pos ( nurl_str_cat
                ( nurl_str_cat3 `type '` nty `' implements trait '` )
                ( nurl_str_cat ( nurl_str_cat3 sub `' but not its supertrait '` sup )
                ( nurl_str_cat3 `' — every '` sub
                ( nurl_str_cat3 `' type must also implement '` sup `'` ) ) ) ) ) }
            {}
        }
    }
}

// emit_missing_defaults: for each trait default not overridden by the impl,
// splice "T" → impl's NURL type name into the stored template, prepend
// "@ mname__ImplMangle", and re-lex/emit via gen_fn_decl.
@ emit_missing_defaults s tname s impl_nurl s impl_mangle s provided s bindings i syms i cg → v {
    : s tparam ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__tparam` ) )
    : ~ s defaults ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__defaults` ) )
    ~ != 0 ( nurl_str_len defaults ) {
        : s mname ( str_first_word defaults )
        = defaults ( str_skip_word defaults )
        ? ( str_contains_word provided mname )
        {}  // overridden: impl's concrete method already emitted
        { : s src ( nurl_sym_get g_trait_syms
            ( nurl_str_cat tname ( nurl_str_cat `__` ( nurl_str_cat mname `__src` ) ) ) )
            : s subst0 ? != 0 ( nurl_str_len tparam )
            ( subst_source_raw src tparam impl_nurl )
            src
            : s subst ( subst_assoc subst0 bindings )  // associated types → impl bindings
            : s mangled ( nurl_str_cat mname ( nurl_str_cat `__` impl_mangle ) )
            : s full_src ( nurl_str_cat `@ ` ( nurl_str_cat mangled ( nurl_str_cat ` ` subst ) ) )
            : i lex2 ( nurl_lex_new full_src `<trait_default>` )
            ( gen_fn_decl lex2 syms cg )
        }
    }
}

// ══════════════════════════════════════════════════════════════════════
// Dynamic trait objects (`%Trait`) — docs/spec.md §4.9.
//
// A `%Trait` value is a fat pointer `%dyn.<Trait> = type { i8*, i8* }`:
//   field 0 = data   — a heap box (nurl_alloc) holding the concrete value
//   field 1 = vtable  — points at a per-impl `[K x i8*]` constant:
//                        slot 0      = concrete destructor void(i8*) (or null)
//                        slots 1..K  = one thunk per flattened trait method
// Construction `( dyn Trait v )` boxes v and pairs it with the impl's vtable.
// A bare-name call `( m d )` whose receiver is a `%dyn.Trait` loads the method
// slot and calls it indirectly through the uniform ABI `<ret>(i8* self, …)`.
//
// Memory safety reuses the whole owned-value machinery: each `%dyn.Trait` gets
// a synthesized Drop impl (`drop__dyn.<Trait>` registered under `drop##%dyn.
// <Trait>`), so a `%dyn.Trait` binding is auto-dropped / journaled exactly like
// any user-`Drop` value — the drop runs the vtable's slot-0 destructor on the
// boxed value, then frees the box.
// ══════════════════════════════════════════════════════════════════════

// pipe_first / pipe_rest: split a `|`-delimited packed string (used for method
// signature parts, since LLVM type strings contain spaces but never `|`).
@ pipe_first s str → s {
    : i n ( nurl_str_len str )
    : ~ i i 0
    ~ & < i n != ( nurl_str_get str i ) 124 { = i + i 1 }
    ^ ( nurl_str_slice str 0 i )
}

@ pipe_rest s str → s {
    : i n ( nurl_str_len str )
    : ~ i i 0
    ~ & < i n != ( nurl_str_get str i ) 124 { = i + i 1 }
    // No `|` separator: return a fresh owned EMPTY heap string (not a bare
    // `` literal). pipe_rest is classified as returning an owned string (its
    // other arm is nurl_str_slice), so a caller `: s x ( pipe_rest … )`
    // auto-drops the result — freeing a `.rodata` literal would SEGV. A
    // zero-length nurl_str_slice mallocs a 1-byte owned buffer, matching that
    // contract exactly (same as pipe_first's empty-first-word case).
    ? >= i n { ^ ( nurl_str_slice str 0 0 ) } {}
    ^ ( nurl_str_slice str + i 1 - n + i 1 )
}

// parse_type_dyn: `% Trait` (type position) → the trait-object type
// `%dyn.<Trait>`. Records the trait as needing an emitted fat-pointer type
// (idempotent). Object-safety is enforced at the concrete use sites (here when
// the trait is already known, and at construction) so a forward-referenced
// trait signature does not spuriously fail before its declaration is scanned.
@ parse_type_dyn i lex → s {
    ( nurl_lex_advance lex )  // consume '%'
    ? ! ( is_ident_tok ( nurl_lex_type lex ) )
    { ( die lex `'%' in a type position must be followed by a trait name (dynamic trait object '%Trait')` ) }
    {}
    : s tname ( nurl_lex_val lex )
    ( lint_note_used tname )
    ( nurl_lex_advance lex )  // consume trait name
    ( dyn_note_needed tname )
    ? != 0 ( nurl_str_len ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__istrait` ) ) )
    { ( dyn_check_object_safe lex tname ) }
    {}
    ^ ( nurl_str_cat `%dyn.` tname )
}

// dyn_note_needed: add `tname` to the set of traits that need a fat-pointer
// type + Drop impl emitted. Idempotent (set semantics over g_dyn_needed).
@ dyn_note_needed s tname → v {
    ? ! ( str_contains_word g_dyn_needed tname )
    { = g_dyn_needed ? == 0 ( nurl_str_len g_dyn_needed )
        tname ( nurl_str_cat3 g_dyn_needed ` ` tname ) }
    {}
}

// dyn_flat_methods: the trait's method set as space-separated "m1 T1 m2 T2 …"
// pairs (method name, declaring trait). The declaring trait tags where each
// method's signature is read from — for a plain trait that is always `tname`;
// the flattened list also carries transitive supertrait methods (diamond
// upcasting) so a `%Sub` object can dispatch a `Super` method.
@ dyn_flat_methods s tname → s {
    // the trait's own methods first, in declaration order
    ( __dyn_flat_add tname tname )
    // then each transitive supertrait's methods (skipping already-listed
    // names — an override lives on the sub, dispatch keeps the first slot)
    : ~ s work ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__supers` ) )
    ~ != 0 ( nurl_str_len work ) {
        : s sup ( str_first_word work ) = work ( str_skip_word work )
        // str_first_word can yield "" on a stray separator space — skip it
        // (a bare "" super would re-enqueue forever, see below).
        ? != 0 ( nurl_str_len sup ) {
            ( __dyn_flat_add tname sup )
            // enqueue the supertrait's OWN supertraits (transitive), but only
            // when it actually has some. Appending `" " + ""` for a super with
            // no supers would leave `work` a single space (len 1, never 0) and
            // loop forever; guarding on non-empty keeps the worklist shrinking.
            : s ss ( nurl_sym_get g_trait_syms ( nurl_str_cat sup `__supers` ) )
            ? != 0 ( nurl_str_len ss )
            { = work ? == 0 ( nurl_str_len work ) ss ( nurl_str_cat3 work ` ` ss ) }
            {}
        } {}
    }
    ^ g_dyn_flat_out
}

@ __dyn_flat_reset → v { = g_dyn_flat_out `` = g_dyn_flat_seen `` }

@ __dyn_flat_add s vtTrait s declTrait → v {
    : ~ s ms ( nurl_sym_get g_trait_syms ( nurl_str_cat declTrait `__methods` ) )
    ~ != 0 ( nurl_str_len ms ) {
        : s m ( str_first_word ms ) = ms ( str_skip_word ms )
        ? ( str_contains_word g_dyn_flat_seen m ) {}
        { = g_dyn_flat_seen ? == 0 ( nurl_str_len g_dyn_flat_seen ) m ( nurl_str_cat3 g_dyn_flat_seen ` ` m )
            = g_dyn_flat_out ? == 0 ( nurl_str_len g_dyn_flat_out )
            ( nurl_str_cat3 m ` ` declTrait )
            ( nurl_str_cat g_dyn_flat_out ( nurl_str_cat4 ` ` m ` ` declTrait ) ) }
    }
}

// dyn_flat_count: number of methods in the flattened vtable (vtable size is
// this + 1 for the drop slot).
@ dyn_flat_count s tname → i {
    ( __dyn_flat_reset )
    : ~ s fl ( dyn_flat_methods tname )
    : ~ i c 0
    ~ != 0 ( nurl_str_len fl ) {
        = fl ( str_skip_word fl )  // method
        = fl ( str_skip_word fl )  // declaring trait
        = c + c 1
    }
    ^ c
}

// dyn_method_slot: 1-based vtable slot of method `m` in `tname`'s flattened
// list (slot 0 is the destructor). -1 if `m` is not a method of the trait.
@ dyn_method_slot s tname s m → i {
    ( __dyn_flat_reset )
    : ~ s fl ( dyn_flat_methods tname )
    : ~ i idx 0
    : ~ i found -1
    ~ != 0 ( nurl_str_len fl ) {
        : s mm ( str_first_word fl ) = fl ( str_skip_word fl )
        = fl ( str_skip_word fl )  // declaring trait
        ? & == found -1 ( seq mm m ) { = found idx } {}
        = idx + idx 1
    }
    ? == found -1 { ^ -1 } {}
    ^ + found 1
}

// dyn_method_decltrait: which trait (the object's own or a supertrait) declares
// method `m` — used to read the method's signature for the call/thunk type.
@ dyn_method_decltrait s tname s m → s {
    ( __dyn_flat_reset )
    : ~ s fl ( dyn_flat_methods tname )
    : ~ s res ``
    ~ != 0 ( nurl_str_len fl ) {
        : s mm ( str_first_word fl ) = fl ( str_skip_word fl )
        : s dt ( str_first_word fl ) = fl ( str_skip_word fl )
        ? & == 0 ( nurl_str_len res ) ( seq mm m ) { = res dt } {}
    }
    ^ res
}

// dyn_sig_parts: parse a SUBSTITUTED method signature "…params… → ret" into the
// packed string  ret|recvmode|recv_llvm[|p1|p2…]  where recvmode ∈ val/inout/
// sink. Non-receiver params of an object-safe method are concrete (no Self), so
// the caller may substitute Self→any concrete type before calling.
@ dyn_sig_parts s subst_sig → s {
    : i sx ( nurl_lex_new subst_sig `<dynsig>` )
    : ~ s recvmode `val`
    ? ( seq ( nurl_lex_val sx ) `inout` ) { = recvmode `inout` ( nurl_lex_advance sx ) } {}
    ? ( seq ( nurl_lex_val sx ) `sink` ) { = recvmode `sink` ( nurl_lex_advance sx ) } {}
    : s recv_llvm ( parse_type sx )
    ? ( is_ident_tok ( nurl_lex_type sx ) ) { ( nurl_lex_advance sx ) } {}  // receiver name
    : ~ s params ``
    ~ & != ( nurl_lex_type sx ) TT_ARROW != ( nurl_lex_type sx ) TT_EOF {
        : s pt ( parse_type sx )
        = params ? == 0 ( nurl_str_len params ) pt ( nurl_str_cat3 params `|` pt )
        ? ( is_ident_tok ( nurl_lex_type sx ) ) { ( nurl_lex_advance sx ) } {}  // param name
    }
    : ~ s ret `void`
    ? == ( nurl_lex_type sx ) TT_ARROW { ( nurl_lex_advance sx ) = ret ( parse_type sx ) } {}
    : s head ( nurl_str_cat4 ret `|` recvmode ( nurl_str_cat `|` recv_llvm ) )
    ^ ? == 0 ( nurl_str_len params ) head ( nurl_str_cat3 head `|` params )
}

// dyn_subst_parts: the sig parts of (declaring trait, method) with Self
// substituted to `to`. For a thunk, `to` is the impl's NURL type name; for a
// call-site fn-pointer type, any concrete type works (object-safe ⇒ Self only
// appears as the receiver, which the caller passes as i8*).
@ dyn_subst_parts s declTrait s m s to → s {
    : s tparam ( nurl_sym_get g_trait_syms ( nurl_str_cat declTrait `__tparam` ) )
    : s rawsig ( nurl_sym_get g_trait_syms ( nurl_str_cat declTrait ( nurl_str_cat `__` ( nurl_str_cat m `__sig` ) ) ) )
    : s subst ? != 0 ( nurl_str_len tparam ) ( subst_source_raw rawsig tparam to ) rawsig
    ^ ( dyn_sig_parts subst )
}

// dyn_call_fnty: the uniform dyn-ABI function-pointer type of method `m` as
// seen at a call site — `<ret> (i8*, p1, p2, …)*`. Self is erased to i8*.
@ dyn_call_fnty s parts → s {
    : s ret ( pipe_first parts )
    : s r1 ( pipe_rest parts )  // recvmode|recv_llvm|params…
    : s rest ( pipe_rest ( pipe_rest r1 ) )  // params… (drop recvmode + recv_llvm)
    // Pure IR text (the vtable fn-ptr bitcast target) — lowered.
    : ~ s out ( nurl_str_cat ( nurl_llty ret ) ` (i8*` )
    : ~ s pr rest
    ~ != 0 ( nurl_str_len pr ) {
        : s pt ( pipe_first pr ) = pr ( pipe_rest pr )
        = out ( nurl_str_cat3 out `, ` ( nurl_llty pt ) )
    }
    ^ ( nurl_str_cat out `)*` )
}

// dyn_check_object_safe: a trait is usable as `%Trait` only if every method can
// be dispatched knowing just an `i8*` self + the trait's signature — i.e. it
// has a Self type parameter, and no method (a) lacks a Self receiver, (b) names
// Self anywhere but the receiver, (c) consumes self by value (`sink`), or (d)
// mentions an associated type. Otherwise a clean diagnostic naming the reason.
@ dyn_check_object_safe i lex s tname → v {
    : s tparam ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__tparam` ) )
    ? == 0 ( nurl_str_len tparam )
    { ( die lex ( nurl_str_cat ( nurl_str_cat3 `trait '` tname `' has no Self type parameter '[T]', so it cannot be a dynamic object '%` )
        ( nurl_str_cat tname `'` ) ) ) }
    {}
    : s assoc ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__assoc` ) )
    : ~ s ms ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__methods` ) )
    ~ != 0 ( nurl_str_len ms ) {
        : s m ( str_first_word ms ) = ms ( str_skip_word ms )
        : s sig ( nurl_sym_get g_trait_syms ( nurl_str_cat tname ( nurl_str_cat `__` ( nurl_str_cat m `__sig` ) ) ) )
        ( dyn_check_method_safe lex tname m sig tparam assoc )
    }
    // Supertraits must be object-safe too (their methods enter the vtable).
    : ~ s sup ( nurl_sym_get g_trait_syms ( nurl_str_cat tname `__supers` ) )
    ~ != 0 ( nurl_str_len sup ) {
        : s s1 ( str_first_word sup ) = sup ( str_skip_word sup )
        ? != 0 ( nurl_str_len ( nurl_sym_get g_trait_syms ( nurl_str_cat s1 `__istrait` ) ) )
        { ( dyn_check_object_safe lex s1 ) } {}
    }
}

@ dyn_check_method_safe i lex s tname s m s sig s tparam s assoc → v {
    : i sx ( nurl_lex_new sig `<objsafe>` )
    ? ( seq ( nurl_lex_val sx ) `sink` )
    { ( die lex ( nurl_str_cat ( nurl_str_cat3 `method '` m `' of trait '` )
        ( nurl_str_cat3 tname `' has a 'sink' (by-value consuming) receiver — not object-safe for '%` ( nurl_str_cat tname `' dispatch; use a by-value or 'inout' receiver` ) ) ) ) }
    {}
    ? ( seq ( nurl_lex_val sx ) `inout` ) { ( nurl_lex_advance sx ) } {}
    ? ! ( seq ( nurl_lex_val sx ) tparam )
    { ( die lex ( nurl_str_cat ( nurl_str_cat3 `method '` m `' of trait '` )
        ( nurl_str_cat3 tname `' has no Self receiver as its first parameter — not object-safe for '%` ( nurl_str_cat tname `'` ) ) ) ) }
    {}
    ( nurl_lex_advance sx )  // receiver type (Self, a single token)
    ? ( is_ident_tok ( nurl_lex_type sx ) ) { ( nurl_lex_advance sx ) } {}  // receiver name
    ~ != ( nurl_lex_type sx ) TT_EOF {
        : s w ( nurl_lex_val sx )
        ? ( seq w tparam )
        { ( die lex ( nurl_str_cat ( nurl_str_cat3 `method '` m `' of trait '` )
            ( nurl_str_cat3 tname `' mentions Self beyond the receiver (a parameter or the return type) — not object-safe for '%` ( nurl_str_cat tname `'` ) ) ) ) }
        {}
        ? & != 0 ( nurl_str_len assoc ) ( str_contains_word assoc w )
        { ( die lex ( nurl_str_cat ( nurl_str_cat3 `method '` m `' of trait '` )
            ( nurl_str_cat3 tname `' uses associated type '` ( nurl_str_cat3 w `' through a dynamic object — not object-safe for '%` ( nurl_str_cat tname `'` ) ) ) ) ) }
        {}
        ( nurl_lex_advance sx )
    }
}

// emit_dyn_method_thunk: emit the uniform-ABI thunk that adapts an i8* self +
// value args into a direct call of the concrete static method
// `@<m>__<impl_mangle>`. Idempotent. Module scope; uses fixed register names.
@ emit_dyn_method_thunk s vtTrait s declTrait s m s impl_nurl s impl_llvm s impl_mangle i cg → v {
    : s slug ( nurl_str_cat vtTrait ( nurl_str_cat `.` ( nurl_str_cat impl_mangle ( nurl_str_cat `.` m ) ) ) )
    : s dk ( nurl_str_cat `dynm##` slug )
    ? != 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms dk ) ) { ^ v } {}
    ( nurl_sym_def g_impl_name_syms dk `1` )
    : s parts ( dyn_subst_parts declTrait m impl_nurl )
    : s ret ( pipe_first parts )
    : s r1 ( pipe_rest parts )
    : s recvmode ( pipe_first r1 )
    : s r2 ( pipe_rest r1 )
    : s recv_llvm ( pipe_first r2 )
    : s params ( pipe_rest r2 )
    // thunk parameter list + inner-call tail (value args passed straight on)
    : ~ s thunk_params `i8* %self`
    : ~ s inner_tail ``
    : ~ s pr params
    : ~ i pidx 1
    ~ != 0 ( nurl_str_len pr ) {
        : s pt ( pipe_first pr ) = pr ( pipe_rest pr )
        : s piece ( nurl_str_cat4 `, ` ( nurl_llty pt ) ` %a` ( nurl_str_int pidx ) )
        = thunk_params ( nurl_str_cat thunk_params piece )
        = inner_tail ( nurl_str_cat inner_tail piece )
        = pidx + pidx 1
    }
    ( nurl_print `define ` ) ( nurl_print ( nurl_llty ret ) ) ( nurl_print ` @__dynm.` ) ( nurl_print slug )
    ( nurl_print `(` ) ( nurl_print thunk_params ) ( nurl_print `) {\nentry:\n` )
    ( nurl_print `  %p = bitcast i8* %self to ` ) ( nurl_print recv_llvm ) ( nurl_print `*\n` )
    : ~ s self_arg ``
    ? ( seq recvmode `val` )
    { ( nurl_print `  %rv = load ` ) ( nurl_print recv_llvm ) ( nurl_print `, ` ) ( nurl_print recv_llvm ) ( nurl_print `* %p\n` )
        = self_arg ( nurl_str_cat3 recv_llvm ` ` `%rv` ) }
    { = self_arg ( nurl_str_cat recv_llvm `* %p` ) }
    : s callee ( nurl_str_cat `@` ( nurl_str_cat m ( nurl_str_cat `__` impl_mangle ) ) )
    : s inner_args ( nurl_str_cat self_arg inner_tail )
    ? ( seq ret `void` )
    { ( nurl_print `  call void ` ) ( nurl_print callee ) ( nurl_print `(` ) ( nurl_print inner_args ) ( nurl_print `)\n  ret void\n}\n` ) }
    { ( nurl_print `  %r = call ` ) ( nurl_print ( nurl_llty ret ) ) ( nurl_print ` ` ) ( nurl_print callee ) ( nurl_print `(` ) ( nurl_print inner_args ) ( nurl_print `)\n  ret ` ) ( nurl_print ( nurl_llty ret ) ) ( nurl_print ` %r\n}\n` ) }
}

// emit_dyn_vtable: emit the per-(trait,impl) vtable constant + its method
// thunks + (if the concrete type owns resources) its destructor thunk. Only
// for traits actually used as objects. Idempotent per (trait, impl type).
@ emit_dyn_vtable s tname s impl_nurl s impl_llvm s impl_mangle i syms i cg → v {
    ? ! ( str_contains_word g_dyn_needed tname ) { ^ v } {}
    : s vk ( nurl_str_cat3 `dynvt##` tname ( nurl_str_cat `##` impl_llvm ) )
    ? != 0 ( nurl_str_len ( nurl_sym_get g_impl_name_syms vk ) ) { ^ v } {}
    ( nurl_sym_def g_impl_name_syms vk `1` )
    // slot 0 — the concrete type's full destructor as a void(i8*) thunk.
    : ~ s slot0 `i8* null`
    ? ( __type_needs_drop impl_llvm syms )
    { ( gen_drop_for_type impl_llvm syms )
        : s dm ( __drop_mangle impl_llvm )
        ( emit_jdrop_thunk impl_llvm dm )
        = slot0 ( nurl_str_cat `i8* bitcast (void(i8*)* @__jdrop_` ( nurl_str_cat dm ` to i8*)` ) ) }
    {}
    // Pass 1: emit each method thunk (idempotent).
    ( __dyn_flat_reset )
    : ~ s fl1 ( dyn_flat_methods tname )
    ~ != 0 ( nurl_str_len fl1 ) {
        : s m ( str_first_word fl1 ) = fl1 ( str_skip_word fl1 )
        : s dt ( str_first_word fl1 ) = fl1 ( str_skip_word fl1 )
        ( emit_dyn_method_thunk tname dt m impl_nurl impl_llvm impl_mangle cg )
    }
    // Pass 2: emit the vtable constant referencing thunks by symbol.
    : i vsize + ( dyn_flat_count tname ) 1
    ( nurl_print `@__vt.` ) ( nurl_print tname ) ( nurl_print `.` ) ( nurl_print impl_mangle )
    ( nurl_print ` = constant [` ) ( nurl_print ( nurl_str_int vsize ) ) ( nurl_print ` x i8*] [ ` )
    ( nurl_print slot0 )
    ( __dyn_flat_reset )
    : ~ s fl2 ( dyn_flat_methods tname )
    ~ != 0 ( nurl_str_len fl2 ) {
        : s m ( str_first_word fl2 ) = fl2 ( str_skip_word fl2 )
        : s dt ( str_first_word fl2 ) = fl2 ( str_skip_word fl2 )
        : s fnty ( dyn_call_fnty ( dyn_subst_parts dt m impl_nurl ) )
        ( nurl_print `, i8* bitcast (` ) ( nurl_print fnty ) ( nurl_print ` @__dynm.` )
        ( nurl_print tname ) ( nurl_print `.` ) ( nurl_print impl_mangle ) ( nurl_print `.` ) ( nurl_print m )
        ( nurl_print ` to i8*)` )
    }
    ( nurl_print ` ]\n` )
}

// emit_dyn_drop_fn: the synthesized Drop for `%dyn.<T>` — run the vtable's
// slot-0 destructor on the boxed value, then free the box. Registered under
// `drop##%dyn.<T>` so the ordinary owned-value drop path picks it up.
@ emit_dyn_drop_fn s tname → v {
    : s dynty ( nurl_str_cat `%dyn.` tname )
    : s mangle ( nurl_str_cat `dyn.` tname )
    ( nurl_print `define void @drop__` ) ( nurl_print mangle ) ( nurl_print `(` ) ( nurl_print dynty ) ( nurl_print ` %v) {\nentry:\n` )
    ( nurl_print `  %data = extractvalue ` ) ( nurl_print dynty ) ( nurl_print ` %v, 0\n` )
    ( nurl_print `  %vt = extractvalue ` ) ( nurl_print dynty ) ( nurl_print ` %v, 1\n` )
    ( nurl_print `  %vtnull = icmp eq i8* %vt, null\n` )
    ( nurl_print `  br i1 %vtnull, label %done, label %hasvt\nhasvt:\n` )
    ( nurl_print `  %slotpp = bitcast i8* %vt to i8**\n` )
    ( nurl_print `  %dropfn = load i8*, i8** %slotpp\n` )
    ( nurl_print `  %dnull = icmp eq i8* %dropfn, null\n` )
    ( nurl_print `  br i1 %dnull, label %freebox, label %rundrop\nrundrop:\n` )
    ( nurl_print `  %f = bitcast i8* %dropfn to void(i8*)*\n` )
    ( nurl_print `  call void %f(i8* %data)\n  br label %freebox\nfreebox:\n` )
    ( nurl_print `  call void @nurl_free(i8* %data)\n  br label %done\ndone:\n  ret void\n}\n` )
    // Register so `: %T x ( dyn … )` bindings auto-drop + journal like any Drop.
    ( nurl_sym_def g_impl_name_syms ( nurl_str_cat `drop##` dynty ) mangle )
    // Panic-unwind journal thunk (loads the fat pointer from an alloca).
    ( emit_jdrop_thunk dynty mangle )
}

// ensure_dyn_types_emitted: at module scope, before parse_program, emit every
// needed `%dyn.<T>` type definition (sized-type allocas need the def first),
// then their synthesized Drop functions.
@ ensure_dyn_types_emitted i syms i cg → v {
    // Pass 1: type definitions.
    : ~ s a g_dyn_needed
    ~ != 0 ( nurl_str_len a ) {
        : s t ( str_first_word a ) = a ( str_skip_word a )
        ( nurl_print `%dyn.` ) ( nurl_print t ) ( nurl_print ` = type { i8*, i8* }\n` )
    }
    // Pass 2: synthesized drop functions (reference the type defs above).
    : ~ s b g_dyn_needed
    ~ != 0 ( nurl_str_len b ) {
        : s t ( str_first_word b ) = b ( str_skip_word b )
        ( emit_dyn_drop_fn t )
    }
}

// scan_dyn_types: a body-aware pre-pass collecting every trait genuinely used
// as an object so its fat-pointer type + Drop are emitted before parse_program.
// Runs after scan_fn_sigs so `__istrait` markers are set. Brace-depth-tracked,
// mirroring scan_fn_sigs / scan_type_names, because the `%` sigil is overloaded:
//
//   * `%` at brace depth 0 is the trait / impl DECLARATION sigil
//     (`% Trait …{`, `% Trait Type {`) — NOT a `%Trait` object type. Its name
//     must NOT be collected: doing so grew a vtable for a NON-object-safe trait
//     (e.g. one with an associated type), whose thunks referenced the raw
//     `%Elem` associated type and failed to compile (the trait_assoc /
//     trait_assoc_import regression).
//   * `%Trait` at brace depth > 0 (a struct field type, or a binding / param
//     type inside a body) is a real object type → collect it.
//   * `( dyn Trait … )` is collected at ANY depth (parens don't change brace
//     depth). This is the authoritative anchor: a dyn object cannot exist
//     without being constructed, so ignoring depth-0 `%Trait` type annotations
//     (function signatures, top-level consts) never misses a reachable trait —
//     its construction site is caught here regardless.
@ scan_dyn_types i lex → v {
    : ~ i bdepth 0
    ~ != ( nurl_lex_type lex ) TT_EOF {
        : i tt ( nurl_lex_type lex )
        ? == tt TT_LBRACE
        { = bdepth + bdepth 1 ( nurl_lex_advance lex ) }
        { ? == tt TT_RBRACE
            { = bdepth - bdepth 1 ( nurl_lex_advance lex ) }
            { ? == tt TT_PERCENT
                { ( nurl_lex_advance lex )  // consume '%'
                    ? & > bdepth 0 ( is_ident_tok ( nurl_lex_type lex ) )
                    { : s nm ( nurl_lex_val lex )
                        ? != 0 ( nurl_str_len ( nurl_sym_get g_trait_syms ( nurl_str_cat nm `__istrait` ) ) )
                        { ( dyn_note_needed nm ) } {}
                        ( nurl_lex_advance lex ) }
                    { ? ( is_ident_tok ( nurl_lex_type lex ) )  // depth-0 header trait name — skip, do not collect
                        { ( nurl_lex_advance lex ) } {} } }
                { ? & ( is_ident_tok tt ) ( seq ( nurl_lex_val lex ) `dyn` )
                    { ( nurl_lex_advance lex )
                        ? ( is_ident_tok ( nurl_lex_type lex ) )
                        { : s nm ( nurl_lex_val lex )
                            ? != 0 ( nurl_str_len ( nurl_sym_get g_trait_syms ( nurl_str_cat nm `__istrait` ) ) )
                            { ( dyn_note_needed nm ) } {} }
                        {} }
                    { ( nurl_lex_advance lex ) } } } }
    }
}

// gen_dyn_construct: `( dyn Trait v )` — box v and pair it with the impl's
// vtable, yielding a `%dyn.Trait` value. lex is positioned at the trait name
// (gen_call consumed '(' and the `dyn` keyword).
@ gen_dyn_construct i lex i syms i cg → s {
    : s tname ( nurl_lex_val lex )
    ( lint_note_used tname )
    ( nurl_lex_advance lex )  // consume trait name
    ( nurl_sym_def syms `__in_call_arg__` `1` )
    : s val ( gen_operand lex syms cg )
    ( nurl_sym_def syms `__in_call_arg__` `` )
    : s ct ( nurl_get_last_type )
    ( expect lex TT_RPAREN )
    ( dyn_check_object_safe lex tname )
    ( dyn_note_needed tname )
    : s implkey ( nurl_str_cat3 tname `##` ct )
    ? == 0 ( nurl_str_len ( nurl_sym_get g_trait_syms implkey ) )
    { ( die lex ( nurl_str_cat ( nurl_str_cat3 `type '` ct `' does not implement trait '` )
        ( nurl_str_cat3 tname `', so it cannot be made into a '%` ( nurl_str_cat tname `' object` ) ) ) ) }
    {}
    : s cmangle ( mangle_type ct )
    : s dynty ( nurl_str_cat `%dyn.` tname )
    // heap-box the concrete value (size via the getelementptr-null trick)
    : s szgep ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print szgep ) ( nurl_print ` = getelementptr ` ) ( nurl_print ( nurl_llty ct ) ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty ct ) ) ( nurl_print `* null, i64 1\n` )
    : s szint ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print szint ) ( nurl_print ` = ptrtoint ` ) ( nurl_print ( nurl_llty ct ) ) ( nurl_print `* ` ) ( nurl_print szgep ) ( nurl_print ` to i64\n` )
    : s box ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print box ) ( nurl_print ` = call i8* @nurl_alloc(i64 ` ) ( nurl_print szint ) ( nurl_print `)\n` )
    : s boxc ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print boxc ) ( nurl_print ` = bitcast i8* ` ) ( nurl_print box ) ( nurl_print ` to ` ) ( nurl_print ( nurl_llty ct ) ) ( nurl_print `*\n` )
    ( nurl_print `  store ` ) ( nurl_print ( nurl_llty ct ) ) ( nurl_print ` ` ) ( nurl_print val ) ( nurl_print `, ` ) ( nurl_print ( nurl_llty ct ) ) ( nurl_print `* ` ) ( nurl_print boxc ) ( nurl_print `\n` )
    // fat pointer { box, bitcast(@__vt.Trait.mangle) }
    : i vsize + ( dyn_flat_count tname ) 1
    : s vti8 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print vti8 ) ( nurl_print ` = bitcast [` ) ( nurl_print ( nurl_str_int vsize ) ) ( nurl_print ` x i8*]* @__vt.` ) ( nurl_print tname ) ( nurl_print `.` ) ( nurl_print cmangle ) ( nurl_print ` to i8*\n` )
    : s f0 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print f0 ) ( nurl_print ` = insertvalue ` ) ( nurl_print dynty ) ( nurl_print ` undef, i8* ` ) ( nurl_print box ) ( nurl_print `, 0\n` )
    : s f1 ( nurl_cg_reg cg )
    ( nurl_print `  ` ) ( nurl_print f1 ) ( nurl_print ` = insertvalue ` ) ( nurl_print dynty ) ( nurl_print ` ` ) ( nurl_print f0 ) ( nurl_print `, i8* ` ) ( nurl_print vti8 ) ( nurl_print `, 1\n` )
    ( nurl_set_last_type dynty )
    ^ f1
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
    // Lint: naming a trait here (decl or impl) references it — an
    // `% Trait ( Type )` impl justifies the import of the trait's
    // defining file by itself.
    ( lint_note_used tname )
    ( nurl_lex_advance lex )  // skip trait name
    // Skip optional type params [T] (already captured during scan)
    ? == ( nurl_lex_type lex ) TT_LBRACK
    { ( nurl_lex_advance lex )
        ~ & != ( nurl_lex_type lex ) TT_RBRACK != ( nurl_lex_type lex ) TT_EOF { ( nurl_lex_advance lex ) }
        ( expect lex TT_RBRACK )  // ']'
    }
    {}
    // Skip optional supertrait clause `: Super…` (captured during scan); its
    // names are TT_IDENT trait names running until the body's '{'.
    ? == ( nurl_lex_type lex ) TT_COLON
    { ( nurl_lex_advance lex )
        ~ & == ( nurl_lex_type lex ) TT_IDENT != ( nurl_lex_type lex ) TT_EOF { ( nurl_lex_advance lex ) }
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
        : ~ s provided ``
        : ~ s bindings ``  // associated-type bindings (re-collected for emit subst)
        ~ & != ( nurl_lex_type lex ) TT_RBRACE != ( nurl_lex_type lex ) TT_EOF {
            ? & == ( nurl_lex_type lex ) TT_IDENT ( seq ( nurl_lex_val lex ) `type` )
            { : s pair ( __parse_assoc_binding lex )
                = bindings ? == 0 ( nurl_str_len bindings )
                pair ( nurl_str_cat bindings ( nurl_str_cat ` ` pair ) ) }
            { ? == ( nurl_lex_type lex ) TT_AT
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
                        // Panic-unwind journal: for the `Drop` trait, emit a
                        // `void(i8*)` thunk that loads the value from its alloca
                        // and runs the just-emitted destructor, so a panic can
                        // replay the typed drop the longjmp skips (§7). One per
                        // Drop impl — naturally deduped (an impl block appears
                        // once). Emitted at module scope right after the impl fn.
                        ? & ( seq tname `Drop` ) ( seq mname `drop` )
                        { ( emit_jdrop_thunk impl_llvm impl_mangle ) }
                        {}
                        // gen_fn_decl_concrete recorded the inout/sink parameter
                        // sets under the MANGLED name (`bump__Counter`), but a
                        // call site dispatches by the BARE method name
                        // (`( bump c )` → call_name `bump`) and looks the sets up
                        // there. Mirror them onto the bare name so an `inout` /
                        // `sink` impl-method argument is passed by address /
                        // moved — without this the receiver was passed BY VALUE
                        // into a `T*` parameter, corrupting memory (segfault).
                        // All impls of a trait method share the trait's parameter
                        // conventions, so the bare-name entry is consistent across
                        // implementing types. Only mirror non-empty sets so an
                        // impl with no inout/sink can't clobber another's entry.
                        : s __impl_io ( nurl_sym_get g_fn_inout mangled )
                        : s __impl_sk ( nurl_sym_get g_fn_sink mangled )
                        ? != 0 ( nurl_str_len __impl_io )
                        { ( nurl_sym_def g_fn_inout mname __impl_io ) } {}
                        ? != 0 ( nurl_str_len __impl_sk )
                        { ( nurl_sym_def g_fn_sink mname __impl_sk ) } {}
                    }
                    { ( die lex `expected method name in impl` ) }
                }
                { ( nurl_lex_advance lex ) } }
        }
        ( expect lex TT_RBRACE )  // consume '}' — clean error if unterminated at EOF
        // Synthesize trait-default copies for any method the impl omitted, with
        // the trait's associated types substituted to this impl's bindings.
        ? != 0 ( nurl_str_len impl_nurl )
        { ( emit_missing_defaults tname impl_nurl impl_mangle provided bindings syms cg ) }
        {}
        // Dynamic-dispatch vtable + method thunks for this impl, when the trait
        // is used as an object anywhere in the program (docs/spec.md §4.9).
        ? != 0 ( nurl_str_len impl_nurl )
        { ( emit_dyn_vtable tname impl_nurl impl_llvm impl_mangle syms cg ) }
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
    : ~ s ta_list ``
    : ~ s mangle_sfx ``
    ~ & != ( nurl_lex_type lex ) TT_RPAREN != ( nurl_lex_type lex ) TT_EOF {
        : ~ s ta_word ``
        ? == ( nurl_lex_type lex ) TT_LPAREN
        { = ta_word ( scan_compound_ta_inner lex syms ) }
        { = ta_word ( capture_type_arg_src lex ) }
        = ta_list ? == 0 ( nurl_str_len ta_list )
        ta_word
        ( nurl_str_cat3 ta_list ` ` ta_word )
        = mangle_sfx ( nurl_str_cat mangle_sfx
        ( nurl_str_cat `__` ( mangle_src_word ta_word ) ) )
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
                    : ~ s tparams ``
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
                        // Lint: generic struct templates never reach
                        // vis_record_type, so register the name here.
                        // This scan recurses into imports without
                        // touching vis_current_src_file — the lexer's
                        // filename is the real defining file. Field
                        // types inside the body (`( Vec A ) data`) are
                        // references in that file too.
                        ( lint_note_def_at sname ( nurl_lex_filename lex ) )
                        ( lint_note_template_src body ( nurl_lex_filename lex ) )
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
                    : ~ s ta_list ``
                    ~ & != ( nurl_lex_type lex ) TT_RPAREN != ( nurl_lex_type lex ) TT_EOF {
                        : ~ s ta ``
                        ? == ( nurl_lex_type lex ) TT_LPAREN
                        { = ta ( scan_compound_ta_inner lex syms ) }
                        { = ta ( capture_type_arg_src lex ) }
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
                : s __gs_key ( __canon_import_key path )
                : s marker ( nurl_sym_get g_generic_struct_syms `__scanned__` )
                ? ( str_contains_word marker __gs_key ) {} {
                    : s new_marker ? == 0 ( nurl_str_len marker ) __gs_key
                    ( nurl_str_cat3 marker ` ` __gs_key )
                    ( nurl_sym_def g_generic_struct_syms `__scanned__` new_marker )
                    : s src2 ( nurl_read_file path )
                    : i lex2 ( nurl_lex_new src2 path )
                    // Track the imported file so its imports resolve
                    // importer-relative (mirrors the other scan passes).
                    : s saved_sf ( vis_current_src_file )
                    ( vis_set_current_src_file path )
                    ( scan_generic_structs lex2 syms )
                    ( vis_set_current_src_file saved_sf )
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
    : ~ i depth 1
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
// shape but emits no IR and calls no parse_* helper: a parse_type
// call inside scan_fn_sigs desyncs the scan. Returns 1 on success,
// 0 on a shape it cannot classify (an anonymous enum type, say); the
// caller then abandons the arity count for that function — a missed
// check, never a wrong one.
@ scan_skip_type i lex → i {
    : i tt ( nurl_lex_type lex )
    ? == tt TT_STAR { ( nurl_lex_advance lex ) ^ ( scan_skip_type lex ) } {}
    ? == tt TT_QUEST { ( nurl_lex_advance lex ) ^ ( scan_skip_type lex ) } {}
    ? == tt TT_QUESTQUEST { ( nurl_lex_advance lex ) ^ ( scan_skip_type lex ) } {}
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
// ── Keyword arguments (default params + named call args) ──────────
//
// scan_fn_sigs records, for every non-generic @-function:
//   <fname>__kw_n        parameter count
//   <fname>__kw_pn_<i>   i-th parameter NAME
//   <fname>__kw_pd_<i>   i-th parameter's default-value SOURCE ("" = none)
//   <fname>__kw_hasdef   "1" if any parameter carries a default
// gen_call consults these to desugar a call that uses `name:` labels or
// omits trailing defaulted arguments into an ordinary positional call.
// A default value is a single source token (literal / const / atom),
// which covers the common cases (`= `Task``, `= 50`, `= F`); a richer
// default can be a named const.

@ __kw_key s fname s tag i idx → s {
    ^ ( nurl_str_cat fname ( nurl_str_cat4 `__kw_` tag `_` ( nurl_str_int idx ) ) )
}

// Trim trailing whitespace from a captured source slice.
@ __kw_trim s raw → s {
    : ~ i n ( nurl_str_len raw )
    ~ > n 0 {
        : i c ( nurl_str_get raw - n 1 )
        ? | | | == c 32 == c 9 == c 13 == c 10
        { = n - n 1 }
        { ^ ( nurl_str_slice raw 0 n ) }
    }
    ^ ( nurl_str_slice raw 0 n )
}

// Evaluate a parameter default's source (e.g. ``Task`` / `50`) through a
// sub-lexer that shares the caller's codegen + symbol state, and return
// the `"<llvm-type> <value>"` piece to splice into a call's argument
// list. The value instruction is emitted into the current output.
@ __kw_emit_default i syms i cg s src → s {
    : i sub ( nurl_lex_new src `<kw-default>` )
    : s v ( gen_operand sub syms cg )
    : s t ( nurl_get_last_type )
    ^ ( nurl_str_cat3 t ` ` v )
}

@ scan_fn_sigs i lex i syms → v {
    // Brace-depth tracker. A `:` struct decl body or any `@`-function body
    // contains `{ ... }`; the `@` inside a closure-shaped struct field
    // type (e.g. `( @ HttpResponse HttpRequest ) handler`) used to fire
    // the function-decl branch below and desync the entire param walk,
    // taking the next ident as a phantom `fname` and the next type as
    // its return type — silently writing a wrong syms[<type>] mapping
    // that later showed up at gen_match's payload reconstruction as a
    // mis-typed `inttoptr i64 ... to %WrongStruct*` against any `! T E`
    // result whose T-arm was the misregistered name. Only process
    // declarations at depth 0; advance silently inside `{ ... }`.
    : ~ i bdepth 0
    ~ != ( nurl_lex_type lex ) TT_EOF {
        ? == ( nurl_lex_type lex ) TT_LBRACE
        { = bdepth + bdepth 1 ( nurl_lex_advance lex ) }
        { ? == ( nurl_lex_type lex ) TT_RBRACE
            { = bdepth - bdepth 1 ( nurl_lex_advance lex ) }
            {
                ? != bdepth 0
                { ( nurl_lex_advance lex ) }
                {
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
                                // Scan the parameter region (from here to the
                                // body `{`) for the `inout` marker, just
                                // as the non-generic branch below does. `inout` is
                                // banned as a parameter NAME so a bare `inout` token
                                // here is exact. This lets a forward call to a
                                // generic `inout` function be rejected cleanly — the
                                // index set itself is computed by
                                // compute_generic_inout_sink at gen_generic_fn_store.
                                : ~ b g_saw_inout F
                                // Capture the parameter-type roster for the
                                // GENERIC fn too (tparam names left in place —
                                // `( Vec A );A`), so the call-site width
                                // coercion can substitute this call's type
                                // args and trunc/extend sized-int arguments.
                                // Abandoning (gpc_ok → F) just skips the
                                // roster, exactly like the non-generic walk.
                                : ~ b gpc_ok T
                                : ~ s gptypes ``
                                ~ & & gpc_ok != ( nurl_lex_type lex ) TT_ARROW
                                != ( nurl_lex_type lex ) TT_EOF
                                { ? & ( is_ident_tok ( nurl_lex_type lex ) )
                                    ( __is_param_marker_word ( nurl_lex_val lex ) )
                                    { ? ( seq ( nurl_lex_val lex ) `inout` )
                                        { = g_saw_inout T } {}
                                        ( nurl_lex_advance lex ) }
                                    {}
                                    : i __gts ( nurl_lex_cur_start lex )
                                    ? == 0 ( scan_skip_type lex )
                                    { = gpc_ok F }
                                    { : i __gte ( nurl_lex_cur_start lex )
                                        : s __gt ( nurl_lex_src_slice lex __gts - __gte __gts )
                                        = gptypes ? == 0 ( nurl_str_len gptypes )
                                        __gt ( nurl_str_cat3 gptypes `;` __gt )
                                        ? ( is_ident_tok ( nurl_lex_type lex ) )
                                        { ( nurl_lex_advance lex ) }
                                        { = gpc_ok F } } }
                                ? gpc_ok
                                { ( nurl_sym_def syms ( nurl_str_cat fname `__ptypes_src` ) gptypes ) }
                                {}
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
                            {  // Walk the parameter region counting parameters —
                                // one `[marker] TYPE
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
                                // Per-parameter type SOURCE spans (`;`-joined),
                                // captured here in the pre-pass so a forward call
                                // can be argument-type-checked. Parsing to LLVM is
                                // deferred to the call site (types resolved there).
                                : ~ s ptypes_src ``
                                ~ & & pc_ok != ( nurl_lex_type lex ) TT_ARROW
                                != ( nurl_lex_type lex ) TT_EOF
                                { ? & ( is_ident_tok ( nurl_lex_type lex ) )
                                    ( __is_param_marker_word ( nurl_lex_val lex ) )
                                    { ? ( seq ( nurl_lex_val lex ) `inout` )
                                        { = saw_inout T } {}
                                        ( nurl_lex_advance lex ) }
                                    {}
                                    : i __pty_s ( nurl_lex_cur_start lex )
                                    ? == 0 ( scan_skip_type lex )
                                    { = pc_ok F }
                                    { : i __pty_e ( nurl_lex_cur_start lex )
                                        : s __pty ( nurl_lex_src_slice lex __pty_s - __pty_e __pty_s )
                                        = ptypes_src ? == 0 ( nurl_str_len ptypes_src )
                                        __pty ( nurl_str_cat3 ptypes_src `;` __pty )
                                        ? ( is_ident_tok ( nurl_lex_type lex ) )
                                        { : s pnm ( nurl_lex_val lex )
                                            ( nurl_lex_advance lex )
                                            ( nurl_sym_def syms ( __kw_key fname `pn` pcount ) pnm )
                                            // Optional default value: `= <single-token>`.
                                            // Only fires when `=` is present, so existing
                                            // param regions scan byte-identically.
                                            ? == ( nurl_lex_type lex ) TT_EQ
                                            { ( nurl_lex_advance lex )
                                                : i kds ( nurl_lex_cur_start lex )
                                                ( nurl_lex_advance lex )
                                                : i kde ( nurl_lex_cur_start lex )
                                                ( nurl_sym_def syms ( __kw_key fname `pd` pcount )
                                                ( __kw_trim ( nurl_lex_src_slice lex kds - kde kds ) ) )
                                                ( nurl_sym_def syms ( nurl_str_cat fname `__kw_hasdef` ) `1` )
                                            }
                                            {}
                                            = pcount + pcount 1 }
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
                                { ( nurl_sym_def syms ( nurl_str_cat fname `__kw_n` ) ( nurl_str_int pcount ) )
                                    ( nurl_sym_def syms ( nurl_str_cat fname `__ptypes_src` ) ptypes_src )
                                    : s ar_key ( nurl_str_cat fname `__arity` )
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
                                    // ret_ty is the raw internal repr —
                                    // a `u`-returning fn records `u8` and
                                    // call sites widen with zext off the
                                    // recorded type itself.
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
                        : ~ s alias ``
                        ? ( is_ident_tok ( nurl_lex_type lex ) )
                        { = alias ( nurl_lex_val lex )
                            ( nurl_lex_advance lex )
                        }
                        {}
                        : s __fs_key ( __canon_import_key path )
                        : s scanned ( nurl_sym_get syms `__scanned_files__` )
                        ? ( str_contains_word scanned __fs_key )
                        {}
                        { : s new_scanned ? == 0 ( nurl_str_len scanned )
                            __fs_key
                            ( nurl_str_cat3 scanned ` ` __fs_key )
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
                            // Parse the parameter types here too (not just skip
                            // tokens) so __ffi_params is registered in the
                            // pre-pass — a FORWARD call to this FFI symbol (the
                            // callee declared LATER in the same file) must still
                            // get its args width-coerced at the call site, or the
                            // wasm call type won't match the declare. Mirrors
                            // gen_ffi_decl's param loop exactly to stay in sync.
                            : ~ s ptypes ``
                            : ~ i pct 0
                            ~ & != ( nurl_lex_type lex ) TT_ARROW != ( nurl_lex_type lex ) TT_EOF
                            { ? == ( nurl_lex_type lex ) TT_ELLIPSIS
                                { ( nurl_lex_advance lex ) }
                                { : s lt ( parse_type lex )
                                    ? ( is_ident_tok ( nurl_lex_type lex ) ) { ( nurl_lex_advance lex ) } {}
                                    = ptypes ? == pct 0 lt ( nurl_str_cat3 ptypes `;` lt )
                                    = pct + pct 1
                                }
                            }
                            ? == ( nurl_lex_type lex ) TT_ARROW
                            { ( nurl_lex_advance lex )
                                : s ret_ty ( parse_type lex )
                                ( nurl_sym_def syms fname ret_ty )
                                ( nurl_sym_def syms ( nurl_str_cat fname `__ffi_params` ) ptypes )
                            }
                            {}
                        }
                        {}
                    }
                    { ? == tt TT_PERCENT
                        { ( scan_impl_decl lex syms ) }
                        { ( nurl_lex_advance lex ) }
                    }
                } } }
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
// Purely lexical + brace-depth-tracked — no parse_type call (a
// parse_type call inside scan_* desyncs the scan). Only depth-0 `:`
// decls are inspected; variant names live inside the `{}`
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
                        : s __tn_key ( __canon_import_key path )
                        : s marker ( nurl_sym_get syms `__tn_scanned__` )
                        ? ( str_contains_word marker __tn_key )
                        {}
                        { : s new_marker ? == 0 ( nurl_str_len marker ) __tn_key
                            ( nurl_str_cat3 marker ` ` __tn_key )
                            ( nurl_sym_def syms `__tn_scanned__` new_marker )
                            : s src2 ( nurl_read_file path )
                            : s eff_src2 ? != 0 ( nurl_str_len alias )
                            { : s names ( collect_alias_targets src2 path )
                                ( alias_rewrite_source src2 names ( nurl_str_cat alias `__` ) )
                            }
                            src2
                            : i lex2 ( nurl_lex_new eff_src2 path )
                            // Track the imported file as current so its own
                            // `$`-imports resolve importer-relative (mirrors
                            // scan_fn_sigs / gen_import_decl).
                            : s saved_sf ( vis_current_src_file )
                            ( vis_set_current_src_file path )
                            ( scan_type_names lex2 syms )
                            ( vis_set_current_src_file saved_sf )
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

// One top-level declaration — the body of parse_program's loop, split out
// so the multi-error recovery frame can wrap exactly one declaration.
@ parse_toplevel_decl i lex i syms i cg → v {
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
    // A bare `|` is the most common near-miss: enums are declared
    // `: | Name { … }`, not `| Name { … }`. (The `:`-less spelling
    // used to be silently skipped — and only "worked" when the enum
    // was also imported under the same name; now it's a diagnostic.)
    ? == tt TT_PIPE { ( die lex `enum declarations start with ': |', not a bare '|' — write ': | Name { Variant... }'` ) }
    // Anything else at the top level is a hard error. The decl loop
    // used to silently advance past stray tokens — which is exactly
    // how an unbalanced-brace function body slipped through: an extra
    // `}` closed the body early, and the leftover statements (`^ x`,
    // a stray `}`, …) leaked here and were swallowed, leaving the
    // truncated function to silently miscompile (undef return) or to
    // desync the scan_fn_sigs pre-pass. Refusing them turns that whole
    // class into a diagnostic at the first leaked token.
    { ( die lex ( nurl_str_cat3
        `unexpected `
        ( __tok_label tt ( nurl_lex_val lex ) )
        ` at the top level — expected a declaration (@ fn, : const/struct/enum, & ffi, $ import, or % trait/impl). A stray '}' or leftover expression here usually means an earlier function body has unbalanced braces.` ) ) }
}

// Runtime entry points for the multi-error machinery, declared via the
// language's own `&` FFI (NOT compiler builtins): the committed bootstrap
// compiler must be able to compile this file, and it predates these
// symbols — an `&` decl needs no compiler support beyond the FFI feature
// itself. Both live in runtime_core.c and resolve from runtime.o.
& `c` @ nurl_recover_nojournal *u fnp *u env → i

& `c` @ nurl_print_buf_unwind → v

// Minimal recover for the compiler's own multi-error frames (nurlc.nu
// imports no stdlib): decompose the closure into (fn, env), run it under
// the JOURNAL-FREE recover variant, free the env. The journal-free
// variant matters: the journalled one makes every nurl_free scan the
// live journal, which would make error-free compilation quadratic in
// per-declaration allocations. The trade is that a panic leaks whatever
// the declaration allocated — fine, the process exits non-zero shortly.
// Returns 0 = completed, 1 = panicked (message via nurl_panic_last_msg).
@ __diag_recover ( @ v ) closure → i {
    : *u fnp # *u closure 0
    : *u env # *u closure 1
    : i rv ( nurl_recover_nojournal fnp env )
    ( nurl_free # s env )
    ^ rv
}

// Does the lexer sit on a token that can start a top-level declaration,
// at column 1? (Canonical nurlfmt source puts every top-level decl at
// column 1, so this is a reliable resync anchor; non-canonical code just
// gets coarser recovery.)
@ __at_toplevel_start i lex → b {
    ? != ( nurl_lex_col lex ) 1 { ^ F } {}
    : i tt ( nurl_lex_type lex )
    ? == tt TT_AT { ^ T } {}
    ? == tt TT_COLON { ^ T } {}
    ? == tt TT_AMP { ^ T } {}
    ? == tt TT_DOLLAR { ^ T } {}
    ? == tt TT_PERCENT { ^ T } {}
    ? == tt TT_PUB { ^ T } {}
    ^ F
}

// Skip the rest of a failed declaration: advance at least one token
// (the error may have fired ON a decl starter), then to the next
// column-1 declaration token or EOF.
@ __diag_resync i lex → v {
    ? != ( nurl_lex_type lex ) TT_EOF { ( nurl_lex_advance lex ) } {}
    ~ & != ( nurl_lex_type lex ) TT_EOF ! ( __at_toplevel_start lex ) {
        ( nurl_lex_advance lex )
    }
}

// The compiler itself panicked (div-by-zero, OOB, …) with no diagnostic
// reported: an internal compiler error, not a user error. Say so loudly
// and ask for a report — the alternative is an opaque abort.
@ __ice_report s file s pm → v {
    ( nurl_eprintln `` )
    ( nurl_eprintln `internal compiler error: nurlc itself panicked` )
    ( nurl_eprintln ( nurl_str_cat `  panic message: ` pm ) )
    ( nurl_eprintln ( nurl_str_cat ( nurl_str_cat3 `  while processing ` file `, near line ` )
    ( nurl_str_int g_stmt_line ) ) )
    ( nurl_eprintln `  this is a bug in nurlc, not in your program — please report it at` )
    ( nurl_eprintln `  https://github.com/nurl-lang/nurl/issues with the source that triggered it.` )
    ( nurl_eprintln ( nurl_str_cat `  nurlc version: ` ( nurl_version ) ) )
    ( nurl_exit 3 )
}

@ parse_program i lex i syms i cg → v {
    ~ != ( nurl_lex_type lex ) TT_EOF {
        // Each top-level declaration compiles under a recovery frame so a
        // diagnostic (die → __nurlc_diag__ panic) skips just that decl and
        // the walk continues — one run reports many errors. Nested calls
        // (imports re-enter parse_program) nest frames; the depth counter
        // keeps die's panic-vs-exit decision right on the way back out.
        = g_diag_recover_active + g_diag_recover_active 1
        : i rv ( __diag_recover \ → v { ( parse_toplevel_decl lex syms cg ) } )
        = g_diag_recover_active - g_diag_recover_active 1
        ? != rv 0 {
            : s pm ( nurl_panic_last_msg )
            ? ( seq pm `__nurlc_diag__` )
            {  // A reported diagnostic. The panic may have unwound out of
                // buffered closure-IR emission — reset the output stack to
                // stdout (post-error IR is garbage; the non-zero exit makes
                // callers discard it) and resync to the next declaration.
                ( nurl_print_buf_unwind )
                ( __diag_resync lex )
            }
            { ? > g_err_count 0
                {  // The compiler lost its footing in state a half-parsed
                    // declaration left behind. The diagnostics above are
                    // real; don't bury them under an ICE report.
                    ( nurl_eprintln `note: stopping early — the compiler could not continue past the errors above` )
                    ( nurl_exit 1 ) }
                { ( __ice_report ( nurl_lex_filename lex ) pm ) }
            }
        } {}
    }
}

// ── Entry point ────────────────────────────────────────────────────

@ nurlc_print_help → v {
    ( nurl_print `nurlc — the NURL compiler. Compiles a .nu source file to LLVM IR on stdout.\n\n` )
    ( nurl_print `usage: nurlc [flags] <file.nu>  >out.ll\n\n` )
    ( nurl_print `flags:\n` )
    ( nurl_print `  --help, -h          print this help and exit\n` )
    ( nurl_print `  --version           print the compiler version and exit\n` )
    ( nurl_print `  --g, -g             emit DWARF debug info (nurl.sh --debug forwards this)\n` )
    ( nurl_print `  --lint              run lint-only diagnostics (e.g. unused imports)\n` )
    ( nurl_print `  --no-borrowck       disable the borrow-checker pass (on by default)\n` )
    ( nurl_print `  --strict-borrowck   run the borrow-checker in strict mode\n` )
    ( nurl_print `  --ffi-host-imports  emit FFI calls as wasm host imports\n` )
    ( nurl_print `\nThe LLVM IR goes to stdout; link it with clang against\n` )
    ( nurl_print `stdlib/runtime.native.o (see docs/BUILDING.md). For a one-step\n` )
    ( nurl_print `source-to-binary build use ./nurl.sh <file.nu> [output].\n` )
}

@ main → v {
    // CLI: `nurlc [--g] [--no-borrowck] <file.nu>`. Optional flags in
    // any order; the lone non-flag argument is the source path.
    //   --g / -g       toggle DWARF emission (nurl.sh forwards --debug)
    //   --no-borrowck  disable the borrow-checker analysis pass; it
    //                  is ON by default
    //   --borrowck     accepted for compatibility — a no-op, since
    //                  the pass is on by default
    : ~ s path ``
    : ~ i ai 1
    ~ < ai ( nurl_argc ) {
        : s a ( nurl_argv ai )
        ? ( seq a `--version` )
        { ( nurl_print ( nurl_version ) ) ( nurl_print `\n` ) ( nurl_exit 0 ) }
        { ? | ( seq a `--help` ) ( seq a `-h` )
            { ( nurlc_print_help ) ( nurl_exit 0 ) }
            { ? | ( seq a `--g` ) ( seq a `-g` )
                { = g_dbg_enabled 1 }
                { ? ( seq a `--lint` )
                    { = g_lint 1 }
                    { ? ( seq a `--borrowck` )
                        { = g_borrowck 1 }
                        { ? ( seq a `--no-borrowck` )
                            { = g_borrowck 0 }
                            { ? ( seq a `--strict-borrowck` )
                                { = g_borrowck 1 = g_strict_borrowck 1 }
                                { ? ( seq a `--ffi-host-imports` )
                                    { = g_ffi_host_imports 1 }
                                    { = path a } } } } } } } }
        = ai + ai 1
    }
    ? == 0 ( nurl_str_len path )
    { ( nurl_eprintln `usage: nurlc [--version] [--g] [--lint] [--no-borrowck | --strict-borrowck] [--ffi-host-imports] <file.nu>` ) ( nurl_exit 1 ) }
    {}
    ? != g_lint 0 { ( lint_init path ) } {}
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
    = g_impl_trait_syms ( nurl_sym_new )
    = g_impl_pos_syms ( nurl_sym_new )
    = g_trait_syms ( nurl_sym_new )
    = g_res_type_syms ( nurl_sym_new )
    = g_closure_defs ( nurl_sym_new )
    = g_closure_types ( nurl_sym_new )
    = g_fn_inout ( nurl_sym_new )
    = g_fn_sink ( nurl_sym_new )
    = g_fn_escapes ( nurl_sym_new )
    = g_fn_invoke_only ( nurl_sym_new )
    = g_pending_escape ( nurl_sym_new )
    = g_fn_ret_param ( nurl_sym_new )
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
    // Every impl across the program is now registered — enforce that each
    // implemented subtrait's supertraits are implemented for the same type.
    ( verify_super_obligations )
    : i lex_tn ( nurl_lex_new src path )
    ( scan_type_names lex_tn syms )
    // Dynamic trait objects (docs/spec.md §4.9): collect every trait used as a
    // `%Trait` object (body-aware, after __istrait markers exist) and emit the
    // `%dyn.<T>` fat-pointer type defs + synthesized Drop functions at module
    // scope, before any function references them.
    : i lex_dyn ( nurl_lex_new src path )
    ( scan_dyn_types lex_dyn )
    ( ensure_dyn_types_emitted syms cg )
    : i lex ( nurl_lex_new src path )
    ? != g_lint 0 { = g_lint_recording 1 } {}
    ( parse_program lex syms cg )
    // Multi-error mode: diagnostics were reported per-declaration and the
    // walk continued. If any fired, fail NOW — the deferred stages below
    // (generic flush, escape resolution, lint) walk state that half-parsed
    // declarations may have left inconsistent, and the emitted IR is
    // already garbage past the first error.
    ? > g_err_count 0
    { ( nurl_eprintln ( nurl_str_cat ( nurl_str_cat3 `error: aborting due to `
        ( nurl_str_int g_err_count ) ` previous error` )
        ? > g_err_count 1 `s` `` ) )
        ( nurl_exit 1 ) }
    {}
    // Stop recording new lint targets before flushing generic
    // monomorphisations — those are synthetic, not the user's source.
    = g_lint_recording 0
    // Emit all deferred generic instantiations collected during compilation.
    ( flush_deferred_instantiations syms cg )
    // Every function (incl. just-flushed generic instantiations) has now
    // compiled, so the escape summaries are final: replay the deferred
    // interprocedural-escape checks parked for forward / generic calls
    // (docs/MEMORY.md §3). May bump g_bck_errors, checked below.
    ( resolve_pending_escapes )
    ( dbg_flush )
    // Unused-symbol lint (--lint): every call site (incl. generic
    // instantiations) has now been seen, so report the unused private
    // functions of the top-level file. No-op unless --lint is set.
    ( lint_report_unused_fns )
    ( lint_report_unused_imports )
    // Borrow-checker diagnostics are errors, not warnings. We let
    // parse_program walk every function so every violation surfaces
    // in one run, then exit non-zero here if any were recorded. A
    // borrow-clean program leaves g_bck_errors at 0 and this is a
    // no-op.
    ? > g_bck_errors 0
    { ( nurl_eprintln ( nurl_str_cat ( nurl_str_cat3 `error: compilation aborted — `
        ( nurl_str_int g_bck_errors )
        ? > g_bck_errors 1 ` borrow-checker violations` ` borrow-checker violation` )
        ` (re-run with --no-borrowck to bypass)` ) )
        ( nurl_exit 1 ) }
    {}
}

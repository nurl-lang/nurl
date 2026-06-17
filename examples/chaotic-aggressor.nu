// ============================================================
// chaotic-aggressor.nu — a HOSTILE pre-1.0 grammar/compiler stress test.
//
// This is the meaner sibling of chaotic-showcase.nu. Where the showcase
// politely combined three corners (float density / recursive ADT / closure
// combinators), the AGGRESSOR's job is to bend the language until something
// creaks — then keep the program valid anyway. Everything below compiles and
// runs; the genuine weaknesses it flushed out are catalogued at the very
// bottom (the "AGGRESSOR LAB") as minimal repros, kept inside comments so the
// file as a whole still builds.
//
// The vehicle is a tiny CONCATENATIVE STACK VM (an RPN "Forth in a teacup").
// One program exercises, simultaneously:
//
//   (1) GENERICS + monomorphisation — a generic `Stack [T]` whose element
//       allocation forwards the type variable into `alloc [T]`, mutated
//       through `inout` exclusive borrows that are themselves forwarded
//       inout→inout across call frames.
//   (2) TRAIT dispatch — a `% Show` trait monomorphised by first-argument
//       LLVM type (`show 42` → i64 impl, `show 3.5` → double impl).
//   (3) A multi-payload recursive-style ENUM (`Op`) destructured by `??`
//       with an OR-PATTERN (`Nop | Halt`), a GUARDED arm (`Bin c ? …`), a
//       2-payload binding (`Clamp lo hi`) and a wildcard — all in one match.
//   (4) HIGHER-ORDER dispatch — the binary operators live in a heap
//       `[ (@ f f f) ]` slice-of-closures jump table, indexed by opcode.
//   (5) CLOSURES THAT RETURN CLOSURES — `compose` returns a closure that
//       captures two other closures (escape + double capture).
//   (6) DENSE PREFIX FLOAT ARITHMETIC with no grouping tokens — a degree-3
//       Horner evaluation written as one nested prefix chain.
//   (7) Compile-time CONST FOLDING, LIFO `defer`, nested member-path
//       assignment, variable-index pointer stores, and nested ternaries.
// ============================================================

$ `stdlib/core/mem.nu`
$ `stdlib/std/float.nu`

// Compile-time const fold: 1 << 6 == 64. Folded by const_eval_int, never
// reaches IR as an expression.
: i STACK_CAP << 1 6

// ── (1) A generic typed stack ───────────────────────────────────────
// The element store is `*T`; `stack_new` forwards the type variable T
// straight into `alloc [T]`. Every mutator takes the stack by `inout`
// (exclusive mutable borrow) so writes hit the caller's binding in place.

: Stack [T] { *T data  i len  i cap }

@ stack_new [T] i cap → ( Stack T ) {
    ^ @ ( Stack T ) { # *T ( alloc [T] cap )  0  cap }
}

@ stack_push [T] inout ( Stack T ) s T v → v {
    // nested member-path assignment + variable-index pointer store:
    // s.data[s.len] = v
    = . . s data . s len v
    = . s len + . s len 1
}

@ stack_pop [T] inout ( Stack T ) s → T {
    = . s len - . s len 1
    ^ . . s data . s len
}

@ stack_peek [T] inout ( Stack T ) s → T {
    ^ . . s data - . s len 1
}

// ── (2) A trait dispatched by concrete first-arg type ───────────────

% Show [T] { @ show T x → v }
% Show f { @ show f x → v { ( nurl_print ( float_to_string x ) ) ( nurl_print `\n` ) } }
% Show i { @ show i x → v { ( nurl_print ( nurl_str_int   x ) ) ( nurl_print `\n` ) } }

// ── (3) The instruction set ─────────────────────────────────────────
// Lit/Bin carry payloads; Clamp carries TWO; Nop/Halt are tag-only so they
// can share an or-pattern. (Deliberately NO 4-payload variant — see the
// AGGRESSOR LAB note on the 3-binding match cap.)

: | Op {
    Lit f
    Bin i
    Dup
    Neg
    Clamp f f
    Nop
    Halt
}

// ── (4)+(7) The interpreter ─────────────────────────────────────────
// `s` is inout and is forwarded inout→inout into every stack mutator.
// `ops` is the closure jump table. One `??` carries every match shape the
// grammar allows at once.

@ vm_run inout ( Stack f ) s [Op prog [ ( @ f f f ) ops → f {
    // LIFO defer: registered first, runs last.
    ; { ( nurl_print `[trace] vm halted, depth=` ) ( nurl_print ( nurl_str_int . s len ) ) ( nurl_print `\n` ) }
    ; { ( nurl_print `[trace] vm starting\n` ) }

    ~ op prog {
        ?? op {
            Lit x       → ( stack_push [f] s x )
            Dup         → { : f t ( stack_peek [f] s ) ( stack_push [f] s t ) }
            Neg         → { : f t ( stack_pop [f] s ) ( stack_push [f] s - 0.0 t ) }
            // 2-payload binding + a nested ternary with zero grouping tokens:
            //   clamp t into [lo,hi] = (t<lo) ? lo : (t>hi) ? hi : t
            Clamp lo hi → {
                : f t ( stack_pop [f] s )
                ( stack_push [f] s ? < t lo lo ? > t hi hi t )
            }
            // GUARDED arm: only valid opcodes 0..3 dispatch through the table.
            // `& >= c 0 <= c 3` is a binary `&` over two binary comparisons.
            Bin c ? & >= c 0 <= c 3 → {
                : f rhs ( stack_pop [f] s )
                : f lhs ( stack_pop [f] s )
                : ( @ f f f ) fn . ops c
                ( stack_push [f] s ( fn lhs rhs ) )
            }
            // OR-PATTERN over two tag-only variants:
            Nop | Halt  → {}
            // Catch-all — required because the guarded Bin arm cannot, on its
            // own, satisfy exhaustiveness (a false guard falls through here).
            _           → ( nurl_print `[trace] bad opcode\n` )
        }
    }
    ^ ( stack_peek [f] s )
}

// ── (5) Closures returning closures: capture-by-snapshot of two closures ─

@ compose ( @ f f ) g ( @ f f ) h → ( @ f f ) {
    ^ \ f x → f { ^ ( g ( h x ) ) }
}

// ── (6) Dense prefix arithmetic: Horner form of 3x³ − 2x² + x − 5 ────
//   (((3·x + -2)·x + 1)·x + -5)   — one nested prefix chain, no parens.
@ poly f x → f {
    ^ + * + * + * 3.0 x -2.0 x 1.0 x -5.0
}

@ main → i {
    ( nurl_print `=== chaotic-aggressor ===\n` )
    ( nurl_print `STACK_CAP (1<<6) = ` ) ( nurl_print ( nurl_str_int STACK_CAP ) ) ( nurl_print `\n` )

    // (4) Build the opcode jump table: 0=add 1=sub 2=mul 3=div.
    : [ ( @ f f f ) ops [ ( @ f f f ) |
        \ f a f b → f { ^ + a b }
        \ f a f b → f { ^ - a b }
        \ f a f b → f { ^ * a b }
        \ f a f b → f { ^ / a b }
    ]

    // The program:  3 4 * 5 +  Dup *  Clamp[0,100]
    //   3*4=12 ; 12+5=17 ; dup→17 17 ; *→289 ; clamp→100
    : [Op prog [Op |
        @ Op { Lit 3.0 }
        @ Op { Lit 4.0 }
        @ Op { Bin 2 }
        @ Op { Lit 5.0 }
        @ Op { Bin 0 }
        @ Op { Nop }
        @ Op { Dup }
        @ Op { Bin 2 }
        @ Op { Clamp 0.0 100.0 }
        @ Op { Halt }
    ]

    // (1) inout stack, forwarded into vm_run which forwards it again.
    : ~ ( Stack f ) st ( stack_new [f] STACK_CAP )
    : f result ( vm_run st prog ops )

    ( nurl_print `vm result = ` ) ( show result )      // (2) trait dispatch on f

    // (5) compose two escaping closures: (x → x+1) then (x → 2x)
    : ( @ f f ) inc   \ f x → f { ^ + x 1.0 }
    : ( @ f f ) dbl   \ f x → f { ^ * x 2.0 }
    : ( @ f f ) xform ( compose dbl inc )              // dbl ∘ inc
    ( nurl_print `2*(result+1) = ` ) ( show ( xform result ) )

    // (6) dense prefix Horner polynomial at x=2 → 3*8 -2*4 +2 -5 = 13
    ( nurl_print `poly(2) = ` ) ( show ( poly 2.0 ) )

    // (2) trait dispatch on i too, to prove monomorphisation split.
    ( nurl_print `opcode count = ` ) ( show . ops length )

    ^ 0
}

// ============================================================
// AGGRESSOR LAB — what actually creaked (verified against the HEAD compiler
// built from compiler/nurlc.nu, not the older playground/MCP deploy). All
// repros are valid per a plain reading of spec/grammar.ebnf yet misbehave;
// kept in comments so this file still compiles.
//
// L1 ★ COMPILER BUG — SLICE ELEMENT ACCESS BY A PARAMETER INDEX → BROKEN IR.
//   `. slice idx` where `idx` is a bare function PARAMETER lowers the index
//   as a load from a stack slot the parameter never got, emitting
//   `load i64, i64*` with an EMPTY pointer operand. nurlc returns 0 with no
//   diagnostic; only clang rejects it ("expected instruction opcode"):
//       @ at [ i xs i k → i { ^ . xs k }          // ← malformed IR
//   Workaround: copy the index into a local first — `: i j k  ^ . xs j`.
//   (Raw-pointer `. ptr param` and a MATCH-BOUND index both lower fine —
//   which is exactly why `vm_run` above, indexing `ops` by the match-bound
//   opcode `c`, is safe. Refactor that `c` into a plain parameter and the
//   function stops compiling.)
//
// L2 ★ COMPILER BUG — TYPE KEYWORD AS A VALUE → INVALID LLVM, NO DIAGNOSTIC.
//   A bare type keyword (v/i/f/…) in operand position lowers to a void-typed
//   SSA value; nurlc returns 0 and emits `add void void, 100`, which only
//   clang rejects ("void type only allowed for function results"):
//       : i x + v 100
//   Same trap behind `~ v xs { … }` (using `v` as a foreach binding); a
//   non-keyword name like `e` instead gives the clean, correct
//   "cannot assign to immutable variable".
//
// L3 — NESTED generic_inst ACCEPTED THOUGH GRAMMAR v2.2 FORBIDS IT.
//   grammar: generic_inst = '(' IDENT IDENT+ ')'  — args are BASE idents.
//   Yet HEAD happily monomorphises a nested application (the `Stack`/`Wrap`
//   shapes above rely on exactly this leniency):
//       : Box [T] { T val }
//       : Wrap [T] { ( Box T ) inner  i tag }     // ( Box T ) as a type arg
//   Either the locked grammar must widen or the compiler must reject this —
//   a spec/impl divergence worth resolving BEFORE the 1.0 grammar lock.
//
// L4 — ESCAPING `:~` CAPTURE SILENTLY SNAPSHOTS (no diagnostic).
//   A counter closure that captures a mutable local and escapes prints
//   1,1,1 (fresh snapshot per call), not 1,2,3 — by-value capture is the
//   documented rule, but a broken counter with zero warning is a sharp edge:
//       @ make_counter → ( @ i ) { : ~ i n 0  ^ \ → i { = n + n 1  ^ n } }
//
// FIXED SINCE v0.9.8 (the playground/MCP deploy) — verified working on HEAD:
//   • 4-payload `??` destructuring: `?? b { Quad a b c d → + + + a b c d … }`
//     compiles and returns the right value (was "undefined identifier 'd'"
//     with a caret on the *next* arm in v0.9.8).
// ============================================================

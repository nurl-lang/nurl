// ============================================================
// showcase.nu — NURL language showcase
// A tiny expression evaluator + utility library
// Demonstrates: generics, traits, enums, pattern match, closures,
//               try-operator, defer, slices, foreach, recursion
// ============================================================


// ── FFI: pull in a few C runtime symbols ─────────────────────
// Note: puts, malloc, free are auto-declared by the compiler runtime


// ── Constants & globals ──────────────────────────────────────
: i  MAX_DEPTH     32
: s  GREETING      `NURL showcase v1\n`
: ~ i eval_count   0           // mutable: counts evaluations


// ── Basic generic identity + pair struct ─────────────────────
@ id [T] T x → T { ^ x }

: Pair {
    s key
    i value
}

@ mk_pair s k i x → Pair {
    ^ @ Pair { k x }
}


// ── A trait with a default-ish implementation per type ───────
% Show {
    @ show i n → s
}

% Show i {
    @ show i n → s { ^ (nurl_str_int n) }
}

% Show b {
    @ show b x → s { ^ ? x `T` `F` }
}


// ── Expression AST as a tagged enum ──────────────────────────
// Ast ::= Num(i)
//       | Neg(*Ast)
//       | Bin(i op, *Ast lhs, *Ast rhs)      // op: 0=+ 1=- 2=* 3=/
: | Ast {
    Num  i
    Neg  * Ast
    Bin  i  * Ast  * Ast
}


// ── Heap-allocate an Ast node (tiny helper) ──────────────────
@ box_ast Ast node → * Ast {
    : * Ast p # * Ast ( malloc Z Ast )
    = . p 0 node        // *p = node  (field 0 of the boxed struct)
    ^ p
}


// ── Evaluator returning an Option (division-by-zero → None) ──
@ eval * Ast e → ? i {
    = eval_count + eval_count 1

    ?? . e 0 {
        Num n        → @ ? i { T n }
        Neg inner    → {
            : vv \ ( eval inner )
            ^ @ ? i { T - 0 vv }
        }
        Bin op l r   → {
            : va \ ( eval l )
            : vb \ ( eval r )
            ? == op 0 @ ? i { T + va vb }
            ? == op 1 @ ? i { T - va vb }
            ? == op 2 @ ? i { T * va vb }
            ? == op 3 {
                ? == vb 0
                    @ ? i { F 0 }           // None on /0
                    @ ? i { T / va vb }
            }
            @ ? i { F 0 }                   // unknown op → None
        }
    }
}


// ── Higher-order: map a closure over a slice, returning new slice
@ map_i [T] [ T src (@ i T) f → [ i {
    : i n   . src length
    : * i buf # * i ( malloc * n 8 )
    : ~ i idx 0
    ~ < idx n {
        : T item . src idx
        = . buf idx ( f item )
        = idx + idx 1
    }
    ^ @ [ i { buf n }
}


// ── Recursive factorial (classic) ────────────────────────────
@ fact i n → i {
    ? <= n 1  1  * n ( fact - n 1 )
}


// ── A function we can map over a slice ──────────────────────
@ bump i x → i { + x 100 }


// ── A demo that wires everything together ───────────────────
@ run_demo → v {
    ( puts GREETING )

    // defer: runs on function exit, LIFO
    ; { ( puts `bye from run_demo\n` ) }

    // Build:  (3 + 4) * -(10 / 2)    → 7 * -5 = -35
    : * Ast three  ( box_ast @ Ast { Num 3 } )
    : * Ast four   ( box_ast @ Ast { Num 4 } )
    : * Ast ten    ( box_ast @ Ast { Num 10 } )
    : * Ast two    ( box_ast @ Ast { Num 2 } )
    : * Ast sum    ( box_ast @ Ast { Bin 0 three four } )
    : * Ast div    ( box_ast @ Ast { Bin 3 ten two } )
    : * Ast neg    ( box_ast @ Ast { Neg div } )
    : * Ast root   ( box_ast @ Ast { Bin 2 sum neg } )

    : ? i result ( eval root )

    ?? result {
        _       → ( puts `evaluated\n` )
    }

    // Map a function over a slice
    : [ i nums [ i | 1 2 3 4 5 ]

    ~ n nums {
        ( puts ( show ( bump n ) ) )
    }

    // Traits dispatching on type
    ( puts ( show 42 ) )
    ( puts ( show T ) )

    // Pair + id
    : Pair p  ( mk_pair `answer` ( id [i] 42 ) )
    ( puts . p key )

    // Division by zero → None propagates via \
    : * Ast zero   ( box_ast @ Ast { Num 0 } )
    : * Ast bad    ( box_ast @ Ast { Bin 3 three zero } )
    : ? i r2 ( eval bad )
    ?? r2 {
        _ → ( puts `(got None as expected)\n` )
    }

    ( puts ( show eval_count ) )
}


// ── Entry point ──────────────────────────────────────────────
@ main → i {
    ( run_demo )
    ( puts ( show ( fact 10 ) ) )       // 3628800
    ^ 0
}

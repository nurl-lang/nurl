// ============================================================
// showcase.nu — NURL language showcase
// A tiny expression evaluator + utility library
// Demonstrates: generics, traits, enums, pattern match, closures,
//               try-operator, defer, slices, foreach, recursion
// ============================================================

// ── FFI: pull in a few C runtime symbols ─────────────────────
// Note: puts is auto-declared by the compiler runtime

$ `stdlib/core/box.nu`
$ `stdlib/core/vec.nu`

// ── Constants & globals ──────────────────────────────────────
: i MAX_DEPTH 32
: s GREETING `NURL showcase v1\n`
: ~ i eval_count 0  // mutable: counts evaluations

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
    @ show i n → s { ^ ( nurl_str_int n ) }
}

% Show b {
    @ show b x → s { ^ ? x `T` `F` }
}

// ── Expression AST as a tagged enum ──────────────────────────
// Ast ::= Num(i)
//       | Neg(*Ast)
//       | Bin(i op, *Ast lhs, *Ast rhs)      // op: 0=+ 1=- 2=* 3=/
: | Ast {
    Num i
    Neg * Ast
    Bin i * Ast * Ast
}

// ── Heap-allocate an Ast node (tiny helper) ──────────────────
// Each node is a Box in the arena `nodes`, which owns it: the trees (which
// share subtrees) go with the arena, and nothing is freed by hand.
unsafe @ box_ast inout ( Vec ( Box Ast ) ) nodes Ast node → *Ast {
    : ( Box Ast ) b ( box_new [Ast] node )
    : *Ast p # *Ast ( box_ptr [Ast] b )
    ( vec_push [( Box Ast )] nodes b )
    ^ p
}

// ── Evaluator returning an Option (division-by-zero → None) ──
unsafe @ eval * Ast e → ?i {
    = eval_count + eval_count 1

    ?? . e 0 {
        Num n → @ ?i { T n }
        Neg inner → {
            : vv \ ( eval inner )
            ^ @ ?i { T - 0 vv }
        }
        Bin op l r → {
            : va \ ( eval l )
            : vb \ ( eval r )
            ? == op 0 @ ?i { T + va vb }
            ? == op 1 @ ?i { T - va vb }
            ? == op 2 @ ?i { T * va vb }
            ? == op 3 {
                ? == vb 0
                @ ?i { F 0 }  // None on /0
                @ ?i { T / va vb }
            }
            @ ?i { F 0 }  // unknown op → None
        }
    }
}

// ── Higher-order: map a closure over a slice, returning a new Vec
@ map_i [T] [T src ( @ i T ) f → ( Vec i ) {
    : i n . src length
    : ( Vec i ) out ( vec_with_cap [i] n )
    : ~ i idx 0
    ~ < idx n {
        : T item . src idx
        ( vec_push [i] out ( f item ) )
        = idx + idx 1
    }
    ^ out
}

// ── Recursive factorial (classic) ────────────────────────────
@ fact i n → i {
    ? <= n 1 1 * n ( fact - n 1 )
}

// ── A function we can map over a slice ──────────────────────
@ bump i x → i { + x 100 }

// ── A demo that wires everything together ───────────────────
unsafe @ run_demo → v {
    ( puts GREETING )

    // defer: runs on function exit, LIFO
    ; { ( puts `bye from run_demo\n` ) }

    // Build:  (3 + 4) * -(10 / 2)    → 7 * -5 = -35
    : ~ ( Vec ( Box Ast ) ) nodes ( vec_new [( Box Ast )] )
    : *Ast three ( box_ast nodes @ Ast { Num 3 } )
    : *Ast four ( box_ast nodes @ Ast { Num 4 } )
    : *Ast ten ( box_ast nodes @ Ast { Num 10 } )
    : *Ast two ( box_ast nodes @ Ast { Num 2 } )
    : *Ast sum ( box_ast nodes @ Ast { Bin 0 three four } )
    : *Ast div ( box_ast nodes @ Ast { Bin 3 ten two } )
    : *Ast neg ( box_ast nodes @ Ast { Neg div } )
    : *Ast root ( box_ast nodes @ Ast { Bin 2 sum neg } )

    : ?i result ( eval root )

    ?? result {
        _ → ( puts `evaluated\n` )
    }

    // Map a function over a slice
    : [i nums [i | 1 2 3 4 5]

    ~ n nums {
        ( puts ( show ( bump n ) ) )
    }

    // Traits dispatching on type
    ( puts ( show 42 ) )
    ( puts ( show T ) )

    // Pair + id
    : Pair p ( mk_pair `answer` ( id [i] 42 ) )
    ( puts . p key )

    // Division by zero → None propagates via \
    : *Ast zero ( box_ast nodes @ Ast { Num 0 } )
    : *Ast bad ( box_ast nodes @ Ast { Bin 3 three zero } )
    : ?i r2 ( eval bad )
    ?? r2 {
        _ → ( puts `(got None as expected)\n` )
    }

    ( puts ( show eval_count ) )
}

// ── Entry point ──────────────────────────────────────────────
@ main → i {
    ( run_demo )
    ( puts ( show ( fact 10 ) ) )  // 3628800
    ^ 0
}

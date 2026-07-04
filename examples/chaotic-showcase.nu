// ============================================================
// chaotic-showcase.nu — an ADVERSARIAL grammar stress test.
//
// Purpose (pre-1.0 grammar lock): the existing example/stdlib corpus is
// broad but structurally narrow — systems/byte-codec code, cellular
// automata, emulators, agents. None of it pushes three corners of the
// language at once. This single file deliberately combines all three to
// see whether Grammar v2.2 is genuinely complete or whether something
// needs to change before the v1.0 lock:
//
//   (A) FLOAT / VECTOR prefix-arithmetic DENSITY — deeply nested
//       prefix `+ * - / .` over a Vec3 type. This is the worst case for
//       fixed prefix arity with no closing token (the open A3 question).
//   (B) DEEP RECURSIVE ADT + multi-payload PATTERN MATCHING — a symbolic
//       expression tree (`Expr`) with `*Expr` children, differentiated
//       and simplified by recursive `??` match. No recursive enum exists
//       anywhere else in the tree.
//   (C) HIGHER-ORDER PARSER COMBINATORS — a parser is a closure
//       `(@ ?*Expr *PState)`; `p_chainl` RETURNS a closure that CAPTURES
//       two other closures + a scalar. Closures-capturing-closures is the
//       hardest case for type-dependent capture + escape analysis.
//
// The pipeline: parse a formula string into an Expr tree (C), symbolically
// differentiate + simplify it (B), then evaluate both over Vec3 math (A).
// ============================================================

$ `stdlib/core/string.nu`
$ `stdlib/core/mem.nu`
$ `stdlib/std/float.nu`

// ── Axis A: Vec3 + dense prefix float arithmetic ────────────────────

: Vec3 { f x f y f z }

@ v3 f x f y f z → Vec3 { ^ @ Vec3 { x y z } }

@ v3_add Vec3 a Vec3 b → Vec3 {
    ^ @ Vec3 { + . a x . b x + . a y . b y + . a z . b z }
}

@ v3_scale Vec3 a f s → Vec3 {
    ^ @ Vec3 { * . a x s * . a y s * . a z s }
}

@ v3_dot Vec3 a Vec3 b → f {
    // + (+ (ax*bx) (ay*by)) (az*bz) — fully nested, no grouping tokens.
    ^ + + * . a x . b x * . a y . b y * . a z . b z
}

@ v3_cross Vec3 a Vec3 b → Vec3 {
    ^ @ Vec3 {
        - * . a y . b z * . a z . b y
        - * . a z . b x * . a x . b z
        - * . a x . b y * . a y . b x
    }
}

@ v3_len Vec3 a → f { ^ ( float_sqrt ( v3_dot a a ) ) }

@ v3_norm Vec3 a → Vec3 { : f l ( v3_len a ) ^ ( v3_scale a / 1.0 l ) }

// ── Axis B: a recursive symbolic-expression ADT ─────────────────────
//
// Children are boxed as `*Expr` (raw pointer payloads). This is the only
// recursive enum in the codebase.

: | Expr {
    Num f
    Var
    Add * Expr * Expr
    Mul * Expr * Expr
    Neg * Expr
    Sin * Expr
    Cos * Expr
}

@ ebox Expr e → *Expr {
    : *Expr p ( alloc [Expr] 1 )
    = . p 0 e
    ^ p
}

@ e_num f x → *Expr { ^ ( ebox @ Expr { Num x } ) }

@ e_var → *Expr { ^ ( ebox @ Expr { Var } ) }

@ e_add * Expr a * Expr b → *Expr { ^ ( ebox @ Expr { Add a b } ) }

@ e_mul * Expr a * Expr b → *Expr { ^ ( ebox @ Expr { Mul a b } ) }

@ e_neg * Expr a → *Expr { ^ ( ebox @ Expr { Neg a } ) }

@ e_sin * Expr a → *Expr { ^ ( ebox @ Expr { Sin a } ) }

@ e_cos * Expr a → *Expr { ^ ( ebox @ Expr { Cos a } ) }

// Evaluate the tree at x = xv. Recursive match with 2-payload binding.
@ e_eval * Expr p f xv → f {
    : Expr e . p 0
    ?? e {
        Num c → c
        Var → xv
        Add a b → + ( e_eval a xv ) ( e_eval b xv )
        Mul a b → * ( e_eval a xv ) ( e_eval b xv )
        Neg a → - 0.0 ( e_eval a xv )
        Sin a → ( float_sin ( e_eval a xv ) )
        Cos a → ( float_cos ( e_eval a xv ) )
    }
}

// Symbolic differentiation d/dx — the autodiff core. Each arm rebuilds a
// fresh subtree from the recursive results.
@ e_diff * Expr p → *Expr {
    : Expr e . p 0
    ?? e {
        Num c → ( e_num 0.0 )
        Var → ( e_num 1.0 )
        Add a b → ( e_add ( e_diff a ) ( e_diff b ) )
        Mul a b → ( e_add ( e_mul ( e_diff a ) b ) ( e_mul a ( e_diff b ) ) )
        Neg a → ( e_neg ( e_diff a ) )
        Sin a → ( e_mul ( e_cos a ) ( e_diff a ) )
        Cos a → ( e_neg ( e_mul ( e_sin a ) ( e_diff a ) ) )
    }
}

// Constant-folding + identity simplification. Nested `??` inside arms —
// pattern-matching depth stress.
@ e_simplify * Expr p → *Expr {
    : Expr e . p 0
    ?? e {
        Add a b → {
            : *Expr sa ( e_simplify a )
            : *Expr sb ( e_simplify b )
            : Expr ea . sa 0
            : Expr eb . sb 0
            ?? ea {
                Num x → ?? eb {
                    Num y → ( e_num + x y )
                    _ → ( e_add sa sb )
                }
                _ → ( e_add sa sb )
            }
        }
        Mul a b → {
            : *Expr sa ( e_simplify a )
            : *Expr sb ( e_simplify b )
            : Expr ea . sa 0
            : Expr eb . sb 0
            ?? ea {
                Num x → ?? eb {
                    Num y → ( e_num * x y )
                    _ → ( e_mul sa sb )
                }
                _ → ( e_mul sa sb )
            }
        }
        _ → ( ebox e )
    }
}

// ── Axis C: parser combinators (closures returning closures) ────────

: PState { s text i len i pos }

@ ps_new s input → *PState {
    : *PState ps ( alloc [PState] 1 )
    = . ps text input
    = . ps len ( nurl_str_len input )
    = . ps pos 0
    ^ ps
}

@ p_peek * PState ps i ch → b {
    ? >= . ps pos . ps len { ^ F } {}
    ^ == ( nurl_str_get . ps text . ps pos ) ch
}

@ p_advance * PState ps → v { = . ps pos + . ps pos 1 }

@ p_skip_ws * PState ps → v { ~ ( p_peek ps 32 ) { ( p_advance ps ) } }

@ p_digit * PState ps → b {
    ? >= . ps pos . ps len { ^ F } {}
    : i c ( nurl_str_get . ps text . ps pos )
    ^ & >= c 48 <= c 57
}

@ p_number * PState ps → ?*Expr {
    : ~ f val 0.0
    : ~ i any 0
    ~ ( p_digit ps ) {
        : i d - ( nurl_str_get . ps text . ps pos ) 48
        = val + * val 10.0 # f d
        ( p_advance ps )
        = any 1
    }
    ? == any 0 { ^ @ ?*Expr { F } } {}
    ? ( p_peek ps 46 ) {
        ( p_advance ps )
        : ~ f scale 0.1
        ~ ( p_digit ps ) {
            : i d - ( nurl_str_get . ps text . ps pos ) 48
            = val + val * scale # f d
            = scale * scale 0.1
            ( p_advance ps )
        }
    } {}
    ^ @ ?*Expr { T ( e_num val ) }
}

// atom := 'x' | number | '(' expr ')' | '-' atom | 's' atom | 'c' atom
@ p_atom * PState ps → ?*Expr {
    ( p_skip_ws ps )
    ? ( p_peek ps 120 ) { ( p_advance ps ) ^ @ ?*Expr { T ( e_var ) } } {}
    ? ( p_peek ps 40 ) {
        ( p_advance ps )
        : ?*Expr inner ( p_expr ps )
        ( p_skip_ws ps )
        ? ( p_peek ps 41 ) { ( p_advance ps ) } {}
        ^ inner
    } {}
    ? ( p_peek ps 45 ) {
        ( p_advance ps )
        : ?*Expr a ( p_atom ps )
        ^ ?? a { T e → @ ?*Expr { T ( e_neg e ) } F → @ ?*Expr { F } }
    } {}
    ? ( p_peek ps 115 ) {
        ( p_advance ps )
        : ?*Expr a ( p_atom ps )
        ^ ?? a { T e → @ ?*Expr { T ( e_sin e ) } F → @ ?*Expr { F } }
    } {}
    ? ( p_peek ps 99 ) {
        ( p_advance ps )
        : ?*Expr a ( p_atom ps )
        ^ ?? a { T e → @ ?*Expr { T ( e_cos e ) } F → @ ?*Expr { F } }
    } {}
    ^ ( p_number ps )
}

// The combinator: left-associative chain of `sub` separated by `opch`,
// folded with `build`. RETURNS a closure that CAPTURES sub, opch, build.
@ p_chainl ( @ ?*Expr * PState ) sub i opch ( @ *Expr * Expr * Expr ) build → ( @ ?*Expr * PState ) {
    ^ \ * PState ps → ?*Expr {
        : ?*Expr first ( sub ps )
        ?? first {
            F → @ ?*Expr { F }
            T lhs → {
                : ~ * Expr acc lhs
                ( p_skip_ws ps )
                ~ ( p_peek ps opch ) {
                    ( p_advance ps )
                    : ?*Expr r ( sub ps )
                    ?? r { T rhs → { = acc ( build acc rhs ) } F → {} }
                    ( p_skip_ws ps )
                }
                @ ?*Expr { T acc }
            }
        }
    }
}

// term := atom (('*') atom)*   — built via the combinator.
@ p_term * PState ps → ?*Expr {
    : ( @ ?*Expr * PState ) mulp ( p_chainl
    \ * PState s → ?*Expr { ( p_atom s ) }
    42
    \ * Expr a * Expr b → *Expr { ( e_mul a b ) } )
    ^ ( mulp ps )
}

// expr := term (('+') term)*   — also via the combinator.
@ p_expr * PState ps → ?*Expr {
    : ( @ ?*Expr * PState ) addp ( p_chainl
    \ * PState s → ?*Expr { ( p_term s ) }
    43
    \ * Expr a * Expr b → *Expr { ( e_add a b ) } )
    ^ ( addp ps )
}

@ pf f x → v { ( nurl_print ( float_to_string x ) ) }

@ main → i {
    // ── Axis A: dense vector math ──────────────────────────────
    : Vec3 a ( v3 1.0 2.0 3.0 )
    : Vec3 b ( v3 4.0 5.0 6.0 )
    ( nurl_print `dot=` ) ( pf ( v3_dot a b ) ) ( nurl_print `\n` )
    ( nurl_print `len=` ) ( pf ( v3_len a ) ) ( nurl_print `\n` )
    : Vec3 c ( v3_cross a b )
    ( nurl_print `cross=` ) ( pf . c x ) ( nurl_print ` ` ) ( pf . c y ) ( nurl_print ` ` ) ( pf . c z ) ( nurl_print `\n` )
    : Vec3 d ( v3_add a ( v3_scale b 2.0 ) )
    ( nurl_print `a+2b.x=` ) ( pf . d x ) ( nurl_print `\n` )

    // ── Axis C: parse a formula ───────────────────────────────
    : s formula `x*x + 3.0*x + s(x)`
    : *PState ps ( ps_new formula )
    : ?*Expr parsed ( p_expr ps )
    ?? parsed {
        F → { ( nurl_print `parse failed\n` ) ^ 1 }
        T tree → {
            // ── Axis B: differentiate + simplify + eval ───────
            : *Expr dtree ( e_simplify ( e_diff tree ) )
            ( nurl_print `f(2)=` ) ( pf ( e_eval tree 2.0 ) ) ( nurl_print `\n` )
            ( nurl_print `f'(2)=` ) ( pf ( e_eval dtree 2.0 ) ) ( nurl_print `\n` )
            ( nurl_print `f(0)=` ) ( pf ( e_eval tree 0.0 ) ) ( nurl_print `\n` )
        }
    }
    ^ 0
}

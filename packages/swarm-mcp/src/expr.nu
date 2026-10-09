// packages/swarm-mcp/src/expr.nu — the phase-1 "kernel": a small, regular
// integer-expression language the cluster evaluates per element.
//
// A workload is a map-reduce: the coordinator ships an expression in one
// variable `x` plus a range and a reduce op; each worker parses the expression
// once, evaluates it for every x in its sub-range, and folds the results. The
// language is deliberately small and regular so a language model can write it
// without docs — and it is the natural precursor to phase 2, where the kernel
// is arbitrary NURL compiled to wasm instead of interpreted here.
//
//   expr    := ternary
//   ternary := logic ( '?' expr ':' ternary )?
//   logic   := compare ( ('&'|'|') compare )*
//   compare := addsub ( ('<'|'<='|'>'|'>='|'=='|'!=') addsub )?
//   addsub  := muldiv ( ('+'|'-') muldiv )*
//   muldiv  := unary  ( ('*'|'/'|'%') unary )*
//   unary   := '-' unary | primary
//   primary := NUM | 'x' | '(' expr ')' | ('min'|'max') '(' expr ',' expr ')'
//            | 'abs' '(' expr ')'
//   NUM     := DIGIT+ ( '.' DIGIT+ )?
//
// The same grammar evaluates in one of two numeric domains, chosen per task by
// the caller (see work.nu `dtype`):
//   • int   — all arithmetic is i64 (truncated division; div/mod by zero → 0).
//   • float — all arithmetic is f64, `x` is the integer index cast to double,
//             div/mod by zero → 0.0. A literal with a '.' (e.g. `0.5`) is a
//             float literal in either mode (truncated toward zero in int mode).
// Comparisons and '&' '|' yield 1/0 (1.0/0.0 in float); any non-zero is "true".
//
// Tokens are kept in two parallel int vectors; the parser builds a flat
// stride-4 node arena (tag,a,b,c) and returns the root index — the resp.nu
// arena pattern, so nesting needs no per-node allocation. An EParser is a
// handle (rcbox): `( eparser_new )`, then `expr_parse`, `eparser_ok`,
// `expr_eval` / `expr_eval_f`; its last owner releases it. Float literals carry
// the f64 bit pattern (via floatbits) in the value slot, so the all-int arena
// holds them losslessly; the float evaluator reinterprets them back.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/core/rcbox.nu`

// ── token kinds ──────────────────────────────────────────────────
// 0 END · 1 INT(val) · 2 X · 3 + · 4 - · 5 * · 6 / · 7 % · 8 < · 9 <= ·
// 10 > · 11 >= · 12 == · 13 != · 14 & · 15 | · 16 ? · 17 : · 18 ( · 19 ) ·
// 20 , · 21 min · 22 max · 23 abs · 24 FLT(f64 bits) · 99 ERROR
// Binary-operator kinds 3..15 are chosen to equal their node tags below.

// ── node tags ────────────────────────────────────────────────────
// 0 INT(a=value) · 1 X · 2 NEG(a) · 3 ADD · 4 SUB · 5 MUL · 6 DIV · 7 MOD ·
// 8 LT · 9 LE · 10 GT · 11 GE · 12 EQ · 13 NE · 14 AND · 15 OR ·
// 16 TERN(a=cond,b=then,c=else) · 17 MIN(a,b) · 18 MAX(a,b) · 19 ABS(a) ·
// 20 FLT(a=f64 bit pattern)

@ __is_digit i c → b { ^ & >= c 48 <= c 57 }

@ __is_alpha i c → b { ^ & >= c 97 <= c 122 }

@ __is_space i c → b { ^ | == c 32 | == c 9 | == c 13 == c 10 }

// ── tokenizer ────────────────────────────────────────────────────
// Fills tk (kinds) / tv (values). Returns F on an unrecognised character.

@ expr_tokenize ( Vec u ) src ( Vec i ) tk ( Vec i ) tv → b {
    : i n ( vec_len [u] src )
    : ~ i i 0
    : ~ b ok T
    ~ & ok < i n {
        : i c ?? ( vec_get [u] src i ) { T x → # i x F → 0 }
        ? ( __is_space c ) { = i + i 1 } {
            ? ( __is_digit c ) {
                : ~ i v 0
                ~ & < i n ( __is_digit ?? ( vec_get [u] src i ) { T x → # i x F → 0 } ) {
                    : i d ?? ( vec_get [u] src i ) { T x → # i x F → 0 }
                    = v + * v 10 - d 48
                    = i + i 1
                }
                // A '.' followed by a digit makes it a float literal; otherwise
                // the '.' is left for the (error) operator path. Float literals
                // carry the f64 bit pattern in tv, tagged as token kind 24.
                : i dot ? < i n ?? ( vec_get [u] src i ) { T x → # i x F → 0 } 0
                : b frac & == dot 46 & < + i 1 n ( __is_digit ?? ( vec_get [u] src + i 1 ) { T x → # i x F → 0 } )
                ? frac {
                    = i + i 1  // consume '.'
                    : ~ f fv # f v
                    : ~ f scale 1.0
                    ~ & < i n ( __is_digit ?? ( vec_get [u] src i ) { T x → # i x F → 0 } ) {
                        : i d ?? ( vec_get [u] src i ) { T x → # i x F → 0 }
                        = scale * scale 10.0
                        = fv + fv / # f - d 48 scale
                        = i + i 1
                    }
                    ( vec_push [i] tk 24 ) ( vec_push [i] tv ( f64_to_bits fv ) )
                } {
                    ( vec_push [i] tk 1 ) ( vec_push [i] tv v )
                }
            } {
                ? ( __is_alpha c ) {
                    : ( Vec u ) word ( vec_new [u] )
                    ~ & < i n ( __is_alpha ?? ( vec_get [u] src i ) { T x → # i x F → 0 } ) {
                        ( vec_push [u] word ?? ( vec_get [u] src i ) { T x → # i x F → 0 } )
                        = i + i 1
                    }
                    : i wl ( vec_len [u] word )
                    ? & == wl 1 == ?? ( vec_get [u] word 0 ) { T x → # i x F → 0 } 120 {
                        ( vec_push [i] tk 2 ) ( vec_push [i] tv 0 )
                    } {
                        : i c0 ?? ( vec_get [u] word 0 ) { T x → # i x F → 0 }
                        : i c1 ? > wl 1 ?? ( vec_get [u] word 1 ) { T x → # i x F → 0 } 0
                        ? & == wl 3 & == c0 109 == c1 105 { ( vec_push [i] tk 21 ) ( vec_push [i] tv 0 ) } {  // min
                            ? & == wl 3 & == c0 109 == c1 97 { ( vec_push [i] tk 22 ) ( vec_push [i] tv 0 ) } {  // max
                                ? & == wl 3 == c0 97 { ( vec_push [i] tk 23 ) ( vec_push [i] tv 0 ) } {  // abs
                                    = ok F
                                } } }
                    }
                } {
                    // operators + punctuation
                    : i c2 ? < + i 1 n ?? ( vec_get [u] src + i 1 ) { T x → # i x F → 0 } 0
                    ? == c 43 { ( vec_push [i] tk 3 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                        ? == c 45 { ( vec_push [i] tk 4 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                            ? == c 42 { ( vec_push [i] tk 5 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                ? == c 47 { ( vec_push [i] tk 6 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                    ? == c 37 { ( vec_push [i] tk 7 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                        ? == c 60 { ? == c2 61 { ( vec_push [i] tk 9 ) = i + i 2 } { ( vec_push [i] tk 8 ) = i + i 1 } ( vec_push [i] tv 0 ) } {
                                            ? == c 62 { ? == c2 61 { ( vec_push [i] tk 11 ) = i + i 2 } { ( vec_push [i] tk 10 ) = i + i 1 } ( vec_push [i] tv 0 ) } {
                                                ? == c 61 { ? == c2 61 { ( vec_push [i] tk 12 ) ( vec_push [i] tv 0 ) = i + i 2 } { = ok F } } {
                                                    ? == c 33 { ? == c2 61 { ( vec_push [i] tk 13 ) ( vec_push [i] tv 0 ) = i + i 2 } { = ok F } } {
                                                        ? == c 38 { ( vec_push [i] tk 14 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                                            ? == c 124 { ( vec_push [i] tk 15 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                                                ? == c 63 { ( vec_push [i] tk 16 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                                                    ? == c 58 { ( vec_push [i] tk 17 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                                                        ? == c 40 { ( vec_push [i] tk 18 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                                                            ? == c 41 { ( vec_push [i] tk 19 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                                                                ? == c 44 { ( vec_push [i] tk 20 ) ( vec_push [i] tv 0 ) = i + i 1 } {
                                                                                    = ok F
                                                                                } } } } } } } } } } } } } } } }
                } } }
    }
    ( vec_push [i] tk 0 ) ( vec_push [i] tv 0 )  // END sentinel
    ^ ok
}

// ── parser → flat node arena ─────────────────────────────────────

: EParserImpl {
    ( Vec i ) tk
    ( Vec i ) tv
    i pos
    ( Vec i ) arena  // stride-4: tag,a,b,c
    b ok
}

// An EParser is a handle on its state in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same parser, and the last owner releases it.
: EParser { s ctl }

unsafe @ EParser_share EParser h → EParser { ^ @ EParser { # s ( rcbox_share # i . h ctl ) } }

@ EParser_drop sink EParser h → v {
    ( mem_forget h )
    ( rcbox_release [EParserImpl] # i . h ctl )
}

// The parser in place. One underscore: shared with work.nu, whose fold opens
// the handle once per chunk and evaluates on the pointer.
unsafe @ _EParser_ptr EParser h → *EParserImpl { ^ ( rcbox_ptr [EParserImpl] # i . h ctl ) }

// A parser with nothing parsed yet (eparser_ok is F until expr_parse succeeds).
unsafe @ eparser_new → EParser {
    ^ @ EParser { # s ( rcbox_new [EParserImpl] @ EParserImpl { ( vec_new [i] ) ( vec_new [i] ) 0 ( vec_new [i] ) F } ) }
}

// Did the last expr_parse accept its source?
unsafe @ eparser_ok EParser p__h → b {
    : *EParserImpl p ( _EParser_ptr p__h )
    ^ . p ok
}

unsafe @ __ep_kind * EParserImpl p → i { ^ ?? ( vec_get [i] . p tk . p pos ) { T x → x F → 0 } }

unsafe @ __ep_val * EParserImpl p → i { ^ ?? ( vec_get [i] . p tv . p pos ) { T x → x F → 0 } }

unsafe @ __ep_adv * EParserImpl p → v { = . p pos + . p pos 1 }

// Push a node, return its index.
unsafe @ __ep_node * EParserImpl p i tag i a i b i c → i {
    : i idx / ( vec_len [i] . p arena ) 4
    ( vec_push [i] . p arena tag )
    ( vec_push [i] . p arena a )
    ( vec_push [i] . p arena b )
    ( vec_push [i] . p arena c )
    ^ idx
}

// Expect+consume a token kind; flag an error if it is not there.
unsafe @ __ep_expect * EParserImpl p i kind → v {
    ? == ( __ep_kind p ) kind { ( __ep_adv p ) } { = . p ok F }
}

unsafe @ __ep_primary * EParserImpl p → i {
    : i k ( __ep_kind p )
    ? == k 1 { : i v ( __ep_val p ) ( __ep_adv p ) ^ ( __ep_node p 0 v 0 0 ) } {}  // INT
    ? == k 24 { : i bits ( __ep_val p ) ( __ep_adv p ) ^ ( __ep_node p 20 bits 0 0 ) } {}  // FLT (f64 bits)
    ? == k 2 { ( __ep_adv p ) ^ ( __ep_node p 1 0 0 0 ) } {}  // X
    ? == k 18 {  // ( expr )
        ( __ep_adv p )
        : i e ( __ep_expr p )
        ( __ep_expect p 19 )
        ^ e
    } {}
    ? | == k 21 == k 22 {  // min(a,b) / max(a,b)
        : i tag ? == k 21 17 18
        ( __ep_adv p )
        ( __ep_expect p 18 )
        : i a ( __ep_expr p )
        ( __ep_expect p 20 )
        : i b ( __ep_expr p )
        ( __ep_expect p 19 )
        ^ ( __ep_node p tag a b 0 )
    } {}
    ? == k 23 {  // abs(a)
        ( __ep_adv p )
        ( __ep_expect p 18 )
        : i a ( __ep_expr p )
        ( __ep_expect p 19 )
        ^ ( __ep_node p 19 a 0 0 )
    } {}
    = . p ok F
    ^ 0
}

unsafe @ __ep_unary * EParserImpl p → i {
    ? == ( __ep_kind p ) 4 { ( __ep_adv p ) ^ ( __ep_node p 2 ( __ep_unary p ) 0 0 ) } {}  // -unary → NEG
    ^ ( __ep_primary p )
}

unsafe @ __ep_muldiv * EParserImpl p → i {
    : ~ i a ( __ep_unary p )
    ~ & . p ok | == ( __ep_kind p ) 5 | == ( __ep_kind p ) 6 == ( __ep_kind p ) 7 {
        : i op ( __ep_kind p )
        ( __ep_adv p )
        : i b ( __ep_unary p )
        = a ( __ep_node p op a b 0 )
    }
    ^ a
}

unsafe @ __ep_addsub * EParserImpl p → i {
    : ~ i a ( __ep_muldiv p )
    ~ & . p ok | == ( __ep_kind p ) 3 == ( __ep_kind p ) 4 {
        : i op ( __ep_kind p )
        ( __ep_adv p )
        : i b ( __ep_muldiv p )
        = a ( __ep_node p op a b 0 )
    }
    ^ a
}

unsafe @ __ep_compare * EParserImpl p → i {
    : i a ( __ep_addsub p )
    : i k ( __ep_kind p )
    ? & . p ok & >= k 8 <= k 13 {
        ( __ep_adv p )
        : i b ( __ep_addsub p )
        ^ ( __ep_node p k a b 0 )
    } {}
    ^ a
}

unsafe @ __ep_logic * EParserImpl p → i {
    : ~ i a ( __ep_compare p )
    ~ & . p ok | == ( __ep_kind p ) 14 == ( __ep_kind p ) 15 {
        : i op ( __ep_kind p )
        ( __ep_adv p )
        : i b ( __ep_compare p )
        = a ( __ep_node p op a b 0 )
    }
    ^ a
}

unsafe @ __ep_expr * EParserImpl p → i {
    : i cond ( __ep_logic p )
    ? & . p ok == ( __ep_kind p ) 16 {  // cond ? then : else
        ( __ep_adv p )
        : i then ( __ep_expr p )
        ( __ep_expect p 17 )
        : i els ( __ep_expr p )
        ^ ( __ep_node p 16 cond then els )
    } {}
    ^ cond
}

// Parse `src` → (arena, root). On any error, ok=0; the caller checks it
// (eparser_ok). The arena stays in the EParser; the root index is the return
// value. A parser can be reused: each parse starts from empty vectors.
unsafe @ expr_parse ( Vec u ) src EParser p__h → i {
    : *EParserImpl p ( _EParser_ptr p__h )
    ( vec_clear [i] . p tk )
    ( vec_clear [i] . p tv )
    ( vec_clear [i] . p arena )
    = . p pos 0
    = . p ok ( expr_tokenize src . p tk . p tv )
    ? ! . p ok { ^ 0 } {}
    : i root ( __ep_expr p )
    // Must consume everything up to END.
    ? != ( __ep_kind p ) 0 { = . p ok F } {}
    ^ root
}

// Let go of `p` now rather than at the end of its owner's scope (optional).
@ eparser_free sink EParser p → v {}

// ── evaluator ────────────────────────────────────────────────────
// Reads the arena through the parser pointer (a borrow), so evaluating does
// not move the arena field out of the parser — the worker evaluates the same
// parsed expression for every x in its sub-range. The public expr_eval /
// expr_eval_f open the handle once; the recursion runs on the pointer.

unsafe @ __ar * EParserImpl p i node i off → i { ^ ?? ( vec_get [i] . p arena + * node 4 off ) { T x → x F → 0 } }

unsafe inline @ expr_eval EParser p__h i node i x → i { ^ ( _expr_eval ( _EParser_ptr p__h ) node x ) }

unsafe @ _expr_eval * EParserImpl p i node i x → i {
    : i tag ( __ar p node 0 )
    : i a ( __ar p node 1 )
    : i b ( __ar p node 2 )
    : i c ( __ar p node 3 )
    ? == tag 0 { ^ a } {}
    ? == tag 20 { ^ # i ( bits_to_f64 a ) } {}  // FLT literal in int mode → truncate
    ? == tag 1 { ^ x } {}
    ? == tag 2 { ^ - 0 ( _expr_eval p a x ) } {}
    ? == tag 3 { ^ + ( _expr_eval p a x ) ( _expr_eval p b x ) } {}
    ? == tag 4 { ^ - ( _expr_eval p a x ) ( _expr_eval p b x ) } {}
    ? == tag 5 { ^ * ( _expr_eval p a x ) ( _expr_eval p b x ) } {}
    ? == tag 6 { : i d ( _expr_eval p b x ) ? == d 0 { ^ 0 } { ^ / ( _expr_eval p a x ) d } } {}
    ? == tag 7 { : i d ( _expr_eval p b x ) ? == d 0 { ^ 0 } { ^ % ( _expr_eval p a x ) d } } {}
    ? == tag 8 { ^ ? < ( _expr_eval p a x ) ( _expr_eval p b x ) 1 0 } {}
    ? == tag 9 { ^ ? <= ( _expr_eval p a x ) ( _expr_eval p b x ) 1 0 } {}
    ? == tag 10 { ^ ? > ( _expr_eval p a x ) ( _expr_eval p b x ) 1 0 } {}
    ? == tag 11 { ^ ? >= ( _expr_eval p a x ) ( _expr_eval p b x ) 1 0 } {}
    ? == tag 12 { ^ ? == ( _expr_eval p a x ) ( _expr_eval p b x ) 1 0 } {}
    ? == tag 13 { ^ ? != ( _expr_eval p a x ) ( _expr_eval p b x ) 1 0 } {}
    ? == tag 14 { ^ ? & != ( _expr_eval p a x ) 0 != ( _expr_eval p b x ) 0 1 0 } {}
    ? == tag 15 { ^ ? | != ( _expr_eval p a x ) 0 != ( _expr_eval p b x ) 0 1 0 } {}
    ? == tag 16 { ? != ( _expr_eval p a x ) 0 { ^ ( _expr_eval p b x ) } { ^ ( _expr_eval p c x ) } } {}
    ? == tag 17 { : i va ( _expr_eval p a x ) : i vb ( _expr_eval p b x ) ^ ? < va vb va vb } {}
    ? == tag 18 { : i va ( _expr_eval p a x ) : i vb ( _expr_eval p b x ) ^ ? > va vb va vb } {}
    ? == tag 19 { : i va ( _expr_eval p a x ) ^ ? < va 0 - 0 va va } {}
    ^ 0
}

// ── float evaluator ──────────────────────────────────────────────
// The f64 dual of expr_eval. Same arena, same tags; `x` arrives already cast to
// double. INT-literal nodes are widened with sitofp; FLT-literal nodes carry the
// f64 bit pattern and are reinterpreted back. Div/mod by zero → 0.0; mod is the
// truncated remainder (a − b·trunc(a/b)), matching the int evaluator's rule.

unsafe inline @ expr_eval_f EParser p__h i node f x → f { ^ ( _expr_eval_f ( _EParser_ptr p__h ) node x ) }

unsafe @ _expr_eval_f * EParserImpl p i node f x → f {
    : i tag ( __ar p node 0 )
    : i a ( __ar p node 1 )
    : i b ( __ar p node 2 )
    : i c ( __ar p node 3 )
    ? == tag 0 { ^ # f a } {}  // INT literal → double
    ? == tag 20 { ^ ( bits_to_f64 a ) } {}  // FLT literal
    ? == tag 1 { ^ x } {}
    ? == tag 2 { ^ - 0.0 ( _expr_eval_f p a x ) } {}
    ? == tag 3 { ^ + ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) } {}
    ? == tag 4 { ^ - ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) } {}
    ? == tag 5 { ^ * ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) } {}
    ? == tag 6 { : f d ( _expr_eval_f p b x ) ? == d 0.0 { ^ 0.0 } { ^ / ( _expr_eval_f p a x ) d } } {}
    ? == tag 7 { : f d ( _expr_eval_f p b x ) ? == d 0.0 { ^ 0.0 } { : f aa ( _expr_eval_f p a x ) ^ - aa * d # f # i / aa d } } {}
    ? == tag 8 { ^ ? < ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) 1.0 0.0 } {}
    ? == tag 9 { ^ ? <= ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) 1.0 0.0 } {}
    ? == tag 10 { ^ ? > ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) 1.0 0.0 } {}
    ? == tag 11 { ^ ? >= ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) 1.0 0.0 } {}
    ? == tag 12 { ^ ? == ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) 1.0 0.0 } {}
    ? == tag 13 { ^ ? != ( _expr_eval_f p a x ) ( _expr_eval_f p b x ) 1.0 0.0 } {}
    ? == tag 14 { ^ ? & != ( _expr_eval_f p a x ) 0.0 != ( _expr_eval_f p b x ) 0.0 1.0 0.0 } {}
    ? == tag 15 { ^ ? | != ( _expr_eval_f p a x ) 0.0 != ( _expr_eval_f p b x ) 0.0 1.0 0.0 } {}
    ? == tag 16 { ? != ( _expr_eval_f p a x ) 0.0 { ^ ( _expr_eval_f p b x ) } { ^ ( _expr_eval_f p c x ) } } {}
    ? == tag 17 { : f va ( _expr_eval_f p a x ) : f vb ( _expr_eval_f p b x ) ^ ? < va vb va vb } {}
    ? == tag 18 { : f va ( _expr_eval_f p a x ) : f vb ( _expr_eval_f p b x ) ^ ? > va vb va vb } {}
    ? == tag 19 { : f va ( _expr_eval_f p a x ) ^ ? < va 0.0 - 0.0 va va } {}
    ^ 0.0
}

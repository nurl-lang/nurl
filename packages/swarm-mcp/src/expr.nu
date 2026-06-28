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
//   primary := INT | 'x' | '(' expr ')' | ('min'|'max') '(' expr ',' expr ')'
//            | 'abs' '(' expr ')'
//
// All arithmetic is i64 (truncated division; division/mod by zero yields 0).
// Comparisons and '&' '|' yield 0/1; any non-zero is "true".
//
// Tokens are kept in two parallel int vectors; the parser builds a flat
// stride-4 node arena (tag,a,b,c) and returns the root index — the resp.nu
// arena pattern, so nesting needs no per-node allocation.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

// ── token kinds ──────────────────────────────────────────────────
// 0 END · 1 INT(val) · 2 X · 3 + · 4 - · 5 * · 6 / · 7 % · 8 < · 9 <= ·
// 10 > · 11 >= · 12 == · 13 != · 14 & · 15 | · 16 ? · 17 : · 18 ( · 19 ) ·
// 20 , · 21 min · 22 max · 23 abs · 99 ERROR
// Binary-operator kinds 3..15 are chosen to equal their node tags below.

// ── node tags ────────────────────────────────────────────────────
// 0 INT(a=value) · 1 X · 2 NEG(a) · 3 ADD · 4 SUB · 5 MUL · 6 DIV · 7 MOD ·
// 8 LT · 9 LE · 10 GT · 11 GE · 12 EQ · 13 NE · 14 AND · 15 OR ·
// 16 TERN(a=cond,b=then,c=else) · 17 MIN(a,b) · 18 MAX(a,b) · 19 ABS(a)

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
                ( vec_push [i] tk 1 ) ( vec_push [i] tv v )
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
                    ( vec_free [u] word )
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

: EParser {
    ( Vec i ) tk
    ( Vec i ) tv
    i pos
    ( Vec i ) arena  // stride-4: tag,a,b,c
    b ok
}

@ __ep_kind * EParser p → i { ^ ?? ( vec_get [i] . p tk . p pos ) { T x → x F → 0 } }

@ __ep_val * EParser p → i { ^ ?? ( vec_get [i] . p tv . p pos ) { T x → x F → 0 } }

@ __ep_adv * EParser p → v { = . p pos + . p pos 1 }

// Push a node, return its index.
@ __ep_node * EParser p i tag i a i b i c → i {
    : i idx / ( vec_len [i] . p arena ) 4
    ( vec_push [i] . p arena tag )
    ( vec_push [i] . p arena a )
    ( vec_push [i] . p arena b )
    ( vec_push [i] . p arena c )
    ^ idx
}

// Expect+consume a token kind; flag an error if it is not there.
@ __ep_expect * EParser p i kind → v {
    ? == ( __ep_kind p ) kind { ( __ep_adv p ) } { = . p ok F }
}

@ __ep_primary * EParser p → i {
    : i k ( __ep_kind p )
    ? == k 1 { : i v ( __ep_val p ) ( __ep_adv p ) ^ ( __ep_node p 0 v 0 0 ) } {}  // INT
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

@ __ep_unary * EParser p → i {
    ? == ( __ep_kind p ) 4 { ( __ep_adv p ) ^ ( __ep_node p 2 ( __ep_unary p ) 0 0 ) } {}  // -unary → NEG
    ^ ( __ep_primary p )
}

@ __ep_muldiv * EParser p → i {
    : ~ i a ( __ep_unary p )
    ~ & . p ok | == ( __ep_kind p ) 5 | == ( __ep_kind p ) 6 == ( __ep_kind p ) 7 {
        : i op ( __ep_kind p )
        ( __ep_adv p )
        : i b ( __ep_unary p )
        = a ( __ep_node p op a b 0 )
    }
    ^ a
}

@ __ep_addsub * EParser p → i {
    : ~ i a ( __ep_muldiv p )
    ~ & . p ok | == ( __ep_kind p ) 3 == ( __ep_kind p ) 4 {
        : i op ( __ep_kind p )
        ( __ep_adv p )
        : i b ( __ep_muldiv p )
        = a ( __ep_node p op a b 0 )
    }
    ^ a
}

@ __ep_compare * EParser p → i {
    : i a ( __ep_addsub p )
    : i k ( __ep_kind p )
    ? & . p ok & >= k 8 <= k 13 {
        ( __ep_adv p )
        : i b ( __ep_addsub p )
        ^ ( __ep_node p k a b 0 )
    } {}
    ^ a
}

@ __ep_logic * EParser p → i {
    : ~ i a ( __ep_compare p )
    ~ & . p ok | == ( __ep_kind p ) 14 == ( __ep_kind p ) 15 {
        : i op ( __ep_kind p )
        ( __ep_adv p )
        : i b ( __ep_compare p )
        = a ( __ep_node p op a b 0 )
    }
    ^ a
}

@ __ep_expr * EParser p → i {
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

// Parse `src` → (arena, root). On any error, ok=0; the caller checks it.
// The arena is returned via the EParser; the root index via the return value.
@ expr_parse ( Vec u ) src * EParser p → i {
    = . p tk ( vec_new [i] )
    = . p tv ( vec_new [i] )
    = . p arena ( vec_new [i] )
    = . p pos 0
    = . p ok ( expr_tokenize src . p tk . p tv )
    ? ! . p ok { ^ 0 } {}
    : i root ( __ep_expr p )
    // Must consume everything up to END.
    ? != ( __ep_kind p ) 0 { = . p ok F } {}
    ^ root
}

// Frees the parser's arena/token vectors AND the struct itself.
@ eparser_free * EParser p → v {
    ( vec_free [i] . p tk )
    ( vec_free [i] . p tv )
    ( vec_free [i] . p arena )
    ( nurl_free # s p )
}

// ── evaluator ────────────────────────────────────────────────────
// Reads the arena through the parser pointer (a borrow), so evaluating does
// not move the arena field out of the parser — the worker evaluates the same
// parsed expression for every x in its sub-range.

@ __ar * EParser p i node i off → i { ^ ?? ( vec_get [i] . p arena + * node 4 off ) { T x → x F → 0 } }

@ expr_eval * EParser p i node i x → i {
    : i tag ( __ar p node 0 )
    : i a ( __ar p node 1 )
    : i b ( __ar p node 2 )
    : i c ( __ar p node 3 )
    ? == tag 0 { ^ a } {}
    ? == tag 1 { ^ x } {}
    ? == tag 2 { ^ - 0 ( expr_eval p a x ) } {}
    ? == tag 3 { ^ + ( expr_eval p a x ) ( expr_eval p b x ) } {}
    ? == tag 4 { ^ - ( expr_eval p a x ) ( expr_eval p b x ) } {}
    ? == tag 5 { ^ * ( expr_eval p a x ) ( expr_eval p b x ) } {}
    ? == tag 6 { : i d ( expr_eval p b x ) ? == d 0 { ^ 0 } { ^ / ( expr_eval p a x ) d } } {}
    ? == tag 7 { : i d ( expr_eval p b x ) ? == d 0 { ^ 0 } { ^ % ( expr_eval p a x ) d } } {}
    ? == tag 8 { ^ ? < ( expr_eval p a x ) ( expr_eval p b x ) 1 0 } {}
    ? == tag 9 { ^ ? <= ( expr_eval p a x ) ( expr_eval p b x ) 1 0 } {}
    ? == tag 10 { ^ ? > ( expr_eval p a x ) ( expr_eval p b x ) 1 0 } {}
    ? == tag 11 { ^ ? >= ( expr_eval p a x ) ( expr_eval p b x ) 1 0 } {}
    ? == tag 12 { ^ ? == ( expr_eval p a x ) ( expr_eval p b x ) 1 0 } {}
    ? == tag 13 { ^ ? != ( expr_eval p a x ) ( expr_eval p b x ) 1 0 } {}
    ? == tag 14 { ^ ? & != ( expr_eval p a x ) 0 != ( expr_eval p b x ) 0 1 0 } {}
    ? == tag 15 { ^ ? | != ( expr_eval p a x ) 0 != ( expr_eval p b x ) 0 1 0 } {}
    ? == tag 16 { ? != ( expr_eval p a x ) 0 { ^ ( expr_eval p b x ) } { ^ ( expr_eval p c x ) } } {}
    ? == tag 17 { : i va ( expr_eval p a x ) : i vb ( expr_eval p b x ) ^ ? < va vb va vb } {}
    ? == tag 18 { : i va ( expr_eval p a x ) : i vb ( expr_eval p b x ) ^ ? > va vb va vb } {}
    ? == tag 19 { : i va ( expr_eval p a x ) ^ ? < va 0 - 0 va va } {}
    ^ 0
}

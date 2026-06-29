// packages/swarm-mcp/tests/expr_test.nu — offline tests for the kernel language.
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/expr_test.nu /tmp/et && /tmp/et

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `src/expr.nu`

// Parse `src`, evaluate at x; -999999 marks a parse error.
@ ev s src i x → i {
    : ( Vec u ) b ( bytes_from_str src )
    : *EParser p # *EParser ( nurl_alloc Z EParser )
    : i root ( expr_parse b p )
    : b okp . p ok
    : ~ i r -999999
    ? okp { = r ( expr_eval p root x ) } {}
    ( eparser_free p ) ( vec_free [u] b )
    ^ r
}

// Float evaluate `src` at x (x cast to double inside).
@ evf s src f x → f {
    : ( Vec u ) b ( bytes_from_str src )
    : *EParser p # *EParser ( nurl_alloc Z EParser )
    : i root ( expr_parse b p )
    : b okp . p ok
    : ~ f r -999.0
    ? okp { = r ( expr_eval_f p root x ) } {}
    ( eparser_free p ) ( vec_free [u] b )
    ^ r
}

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_print_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_print_int b ) ( nurl_print `\n` )
}

// Float assert: pass if |a-b| < 1e-9.
@ pf s label f a f b → v {
    : f d - a b
    : f ad ? < d 0.0 - 0.0 d d
    ( nurl_print label ) ( nurl_print ( nurl_str_float a ) )
    ( nurl_print ? < ad 0.000000001 ` ~= ` ` != ` ) ( nurl_print ( nurl_str_float b ) ) ( nurl_print `\n` )
}

@ main → i {
    ( pi `x*x @5:        ` ( ev `x*x` 5 ) 25 )
    ( pi `2+3*4:         ` ( ev `2+3*4` 0 ) 14 )
    ( pi `(2+3)*4:       ` ( ev `(2+3)*4` 0 ) 20 )
    ( pi `x*x-7*x @10:   ` ( ev `x*x-7*x` 10 ) 30 )
    ( pi `x/3 @7:        ` ( ev `x/3` 7 ) 2 )
    ( pi `x%2 @7:        ` ( ev `x%2` 7 ) 1 )
    ( pi `x%2==0 @4:     ` ( ev `x%2==0` 4 ) 1 )
    ( pi `x%2==0 @3:     ` ( ev `x%2==0` 3 ) 0 )
    ( pi `-x @5:         ` ( ev `-x` 5 ) -5 )
    ( pi `abs(-x) @5:    ` ( ev `abs(-x)` 5 ) 5 )
    ( pi `min(x,10) @3:  ` ( ev `min(x,10)` 3 ) 3 )
    ( pi `min(x,10) @20: ` ( ev `min(x,10)` 20 ) 10 )
    ( pi `max(x,10) @20: ` ( ev `max(x,10)` 20 ) 20 )
    ( pi `x>5?x:0 @7:    ` ( ev `x>5 ? x : 0` 7 ) 7 )
    ( pi `x>5?x:0 @3:    ` ( ev `x>5 ? x : 0` 3 ) 0 )
    ( pi `x>2 & x<9 @5:  ` ( ev `x>2 & x<9` 5 ) 1 )
    ( pi `x>2 & x<9 @9:  ` ( ev `x>2 & x<9` 9 ) 0 )
    ( pi `x==3 | x==7 @7:` ( ev `x==3 | x==7` 7 ) 1 )
    ( pi `div0 x/0 @5:   ` ( ev `x/0` 5 ) 0 )
    ( pi `nested @4:     ` ( ev `(x+1)*(x+1)` 4 ) 25 )
    // parse errors → -999999
    ( pi `err 'x*':      ` ( ev `x*` 0 ) -999999 )
    ( pi `err 'x y':     ` ( ev `x y` 0 ) -999999 )
    ( pi `err 'foo(x)':  ` ( ev `foo(x)` 0 ) -999999 )
    // float-domain evaluation (expr_eval_f)
    ( pf `f x*0.5 @5:    ` ( evf `x*0.5` 5.0 ) 2.5 )
    ( pf `f 1.0/(x*x)@2: ` ( evf `1.0/(x*x)` 2.0 ) 0.25 )
    ( pf `f x+0.25 @3:   ` ( evf `x+0.25` 3.0 ) 3.25 )
    ( pf `f 0.1+0.2 @0:  ` ( evf `0.1+0.2` 0.0 ) 0.3 )
    ( pf `f x/0.0 @5:    ` ( evf `x/0.0` 5.0 ) 0.0 )
    ( pf `f x>2.5?1.5:0 @3:` ( evf `x>2.5 ? 1.5 : 0.0` 3.0 ) 1.5 )
    ( pf `f abs(-x)@4:   ` ( evf `abs(-x)` 4.0 ) 4.0 )
    ( pf `f min(x,2.5)@9:` ( evf `min(x,2.5)` 9.0 ) 2.5 )
    // int-mode sees a float literal as truncated
    ( pi `i 3.9 trunc:   ` ( ev `3.9` 0 ) 3 )
    ^ 0
}

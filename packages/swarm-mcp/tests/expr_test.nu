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

@ pi s label i a i b → v {
    ( nurl_print label ) ( nurl_print_int a )
    ( nurl_print ? == a b ` == ` ` != ` ) ( nurl_print_int b ) ( nurl_print `\n` )
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
    ^ 0
}

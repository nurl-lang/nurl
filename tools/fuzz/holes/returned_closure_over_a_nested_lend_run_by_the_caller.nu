// returned_closure_over_a_nested_lend_run_by_the_caller: `( mk ( first ( vec_at vvv 0 ) ) )`
// Closed: a call's returned-closure effects are a member of #686's node graph of their own, so a copy, a join, a block or an arm's `=` of the result carries them; an argument written as a join, a block, a `??`, a field of an element or a nested lend names the bindings its source expression does (agora #817).
// main 0aeaa321 (+#1846): accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #817: a returned closure over a nested lend
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ first ( Vec ( Vec u ) ) vv → ( Vec u ) { ^ ( vec_at [( Vec u )] vv 0 ) }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec ( Vec ( Vec u ) ) ) vvv ( vec_new [( Vec ( Vec u ) )] )
    ( vec_push [( Vec ( Vec u ) )] vvv ( vec_new [( Vec u )] ) )
    ( vec_push [( Vec u )] ( vec_at [( Vec ( Vec u ) )] vvv 0 ) ( vec_new [u] ) )
    ( vec_push [u] ( first ( vec_at [( Vec ( Vec u ) )] vvv 0 ) ) 7 )
    : ( @ v ) c ( mk ( first ( vec_at [( Vec ( Vec u ) )] vvv 0 ) ) )
    : ( Slice u ) sl ( slice_from_vec [u] ( first ( vec_at [( Vec ( Vec u ) )] vvv 0 ) ) )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

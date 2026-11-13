// returned_closure_over_a_field_of_an_element_run_by_the_caller: `( mk . ( vec_at [W] ws 0 ) xs )`
// Closed: a call's returned-closure effects are a member of #686's node graph of their own, so a copy, a join, a block or an arm's `=` of the result carries them; an argument written as a join, a block, a `??`, a field of an element or a nested lend names the bindings its source expression does (agora #817).
// main 0aeaa321 (+#1846): accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #817: a returned closure over a field of an element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

: W { ( Vec u ) xs i n }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Vec W ) ws ( vec_new [W] )
    ( vec_push [W] ws @ W { xs 1 } )
    : ( @ v ) c ( mk . ( vec_at [W] ws 0 ) xs )
    : ( Slice u ) sl ( slice_from_vec [u] . ( vec_at [W] ws 0 ) xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

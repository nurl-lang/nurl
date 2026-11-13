// returned_closure_over_a_join_argument_run_by_the_caller: `( mk ? k xs ys )`
// Closed: a call's returned-closure effects are a member of #686's node graph of their own, so a copy, a join, a block or an arm's `=` of the result carries them; an argument written as a join, a block, a `??`, a field of an element or a nested lend names the bindings its source expression does (agora #817).
// main 0aeaa321 (+#1846): accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #817: a returned closure over a join argument
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( Vec u ) ys ( vec_new [u] )
    : b k > ( vec_len [u] xs ) 0
    : ( @ v ) c ( mk ? k xs ys )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

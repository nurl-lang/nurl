// copy_of_a_returned_closure_run_by_the_caller: `: c ( mk xs )` then `: d c`, `( d )` after a slice of xs
// Closed: a call's returned-closure effects are a member of #686's node graph of their own, so a copy, a join, a block or an arm's `=` of the result carries them; an argument written as a join, a block, a `??`, a field of an element or a nested lend names the bindings its source expression does (agora #817).
// main 0aeaa321 (+#1846): accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #817: a copy of a returned closure run
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`
$ `stdlib/std/rc.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( mk xs )
    : ( @ v ) d c
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

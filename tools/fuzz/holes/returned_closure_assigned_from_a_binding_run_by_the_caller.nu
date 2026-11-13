// returned_closure_assigned_from_a_binding_run_by_the_caller: `= d c` of a returned closure
// Closed: a call's returned-closure effects are a member of #686's node graph of their own, so a copy, a join, a block or an arm's `=` of the result carries them; an argument written as a join, a block, a `??`, a field of an element or a nested lend names the bindings its source expression does (agora #817).
// main 0aeaa321 (+#1846): accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #817: a returned closure assigned from a binding
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
    : ~ ( @ v ) d \ → v {}
    = d c
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

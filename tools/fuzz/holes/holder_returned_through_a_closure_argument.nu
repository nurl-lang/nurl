// holder_returned_through_a_closure_argument: a closure handed to a function hands back a holder viewing the String it is called with.
// Closed: what a function hands back views of its parameters is its borrow walk's answer where it returns (g_fn_rviews); an indirect callee answers with what it may run (a dyn method's impls, a closure node's members), and a callee parked until the module has compiled parks its caller behind it (agora #422).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #422: a closure handed to a function hands back a holder viewing the String it is called with
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ apply ( @ ( Vec s ) String ) f String s → ( Vec s ) { ^ ( f s ) }

@ main → i {
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String s ( string_from `a heap string long enough to be on the heap for sure` )
        = hold ( apply \ String x → ( Vec s ) { : ( Vec s ) h ( vec_new [s] ) ( vec_push [s] h ( string_data x ) ) ^ h } s )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}

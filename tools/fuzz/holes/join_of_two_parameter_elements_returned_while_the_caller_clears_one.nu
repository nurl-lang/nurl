// join_of_two_parameter_elements_returned_while_the_caller_clears_one: agora #335 — a `?` join of two parameters' elements bound and returned, which the return copies wherever the binding owns nothing: the caller holds an owned copy, so clearing one argument while holding it is safe, and was refused (formal's v2c).
// Closed: a take through a binding's `vec_get` slot empties the slot only where no `=` around a loop can have re-pointed the binding (a mutable binding bound outside a loop around the use is copied there instead, __vget_live), and a payload read out of a binding is copied only where that binding owns nothing on the path (__payload_owner_flag; agora #335).
// main: refused ('s' borrows from 'qs', which ended … passed to 'vec_clear'); accepted and clean before #1465.
// map: §7.6 | A2 | runs-clean | - | agora #335: a returned join of parameter elements is a copy, not a lend
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick ( Vec String ) ps ( Vec String ) qs2 i k → String {
    : String r ? == k 1 ( vec_at [String] qs2 0 ) ( vec_at [String] ps 0 )
    ^ r
}

@ main → i {
    : ( Vec String ) qs ( vec_new [String] )
    ( vec_push [String] qs ( string_from `a parameter element long enough for the heap` ) )
    : ( Vec String ) ws ( vec_new [String] )
    ( vec_push [String] ws ( string_from `another parameter element long enough for the heap` ) )
    : String s ( pick qs ws 0 )
    ( vec_clear [String] qs )
    ( nurl_println ( string_data s ) )
    ^ 0
}

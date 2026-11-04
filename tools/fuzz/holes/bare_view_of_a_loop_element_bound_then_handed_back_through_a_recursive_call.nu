// bare_view_of_a_loop_element_bound_then_handed_back_through_a_recursive_call: agora #471 — `pick2 a b k` binds `( pick2 b a 0 )` and hands it back; the caller clears the Vec the view is of, then reads it
// Closed: a view bound to a callee's walk answer `2` keeps that answer's sources (`rva_`), so handing the binding back hands the answer on — for those sources only (agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a loop element bound from a recursive call and handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick2 ( Vec String ) a ( Vec String ) b i k → s {
    ? == k 0 { ~ x a { ^ ( string_data x ) } } {}
    ? == k 1 {
        : s r ( pick2 b a 0 )
        ^ r
    } {}
    ^ `none`
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string of t, kept` ) )
    : ( Vec String ) u ( vec_new [String] )
    ( vec_push [String] u ( string_from `a string of u, cleared before the view is read` ) )
    : s v ( pick2 t u 1 )
    ( vec_clear [String] u )
    ( nurl_println v )
    ^ 0
}

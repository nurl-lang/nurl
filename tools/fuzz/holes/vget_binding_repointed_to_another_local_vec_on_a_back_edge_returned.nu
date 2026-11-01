// vget_binding_repointed_to_another_local_vec_on_a_back_edge_returned: agora #335 — the same, re-pointed at another local Vec's element: the take emptied the first Vec's slot while the second still dropped what was returned (formal's l1).
// Closed: a take through a binding's `vec_get` slot empties the slot only where no `=` around a loop can have re-pointed the binding (a mutable binding bound outside a loop around the use is copied there instead, __vget_live), and a payload read out of a binding is copied only where that binding owns nothing on the path (__payload_owner_flag; agora #335).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #335: a vec_get binding re-pointed at another local Vec on a back edge
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element of vs long enough for the heap` ) )
    : ( Vec String ) us ( vec_new [String] )
    ( vec_push [String] us ( string_from `an element of us long enough for the heap` ) )
    : ~ ? String o ( vec_get [String] vs 0 )
    : ~ i j 0
    ~ < j 2 {
        ?? o { T e → { ? == j k { ^ e } {} } F → {} }
        = o ( vec_get [String] us 0 )
        = j + j 1
    }
    ^ ( string_from `none` )
}

@ main → i {
    : String b ( pick 1 )
    ( nurl_println ( string_data b ) )
    ^ 0
}

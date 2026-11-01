// vget_binding_repointed_to_the_same_vec_on_a_back_edge_returned: agora #335 — the same, re-pointed at the same Vec's element 1: the take emptied slot 0 while slot 1 still dropped what was returned (formal's l3).
// Closed: a take through a binding's `vec_get` slot empties the slot only where no `=` around a loop can have re-pointed the binding (a mutable binding bound outside a loop around the use is copied there instead, __vget_live), and a payload read out of a binding is copied only where that binding owns nothing on the path (__payload_owner_flag; agora #335).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #335: a vec_get binding re-pointed within its Vec on a back edge
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `the first element of vs long enough for the heap` ) )
    ( vec_push [String] vs ( string_from `the second element of vs long enough for the heap` ) )
    : ~ ? String o ( vec_get [String] vs 0 )
    : ~ i j 0
    ~ < j 2 {
        ?? o { T e → { ? == j k { ^ e } {} } F → {} }
        = o ( vec_get [String] vs 1 )
        = j + j 1
    }
    ^ ( string_from `none` )
}

@ main → i {
    : String b ( pick 1 )
    ( nurl_println ( string_data b ) )
    ^ 0
}

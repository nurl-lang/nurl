// vget_binding_given_an_owned_value_on_one_path_payload_returned: agora #335 — a mutable binding of a local Vec's `vec_get`, given a fresh owned option on one path, has its payload returned: it was copied on that path too while the binding's flag was cleared, so the fresh string was freed by no one (formal's a3b).
// Closed: a take through a binding's `vec_get` slot empties the slot only where no `=` around a loop can have re-pointed the binding (a mutable binding bound outside a loop around the use is copied there instead, __vget_live), and a payload read out of a binding is copied only where that binding owns nothing on the path (__payload_owner_flag; agora #335).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | - | agora #335: a vec_get binding given an owned value on one path, its payload returned
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick i k → String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string long enough for the heap` ) )
    : ~ ? String o ( vec_get [String] vs 0 )
    ? == k 1 { = o @ ?String { T ( string_from `a fresh string long enough for the heap` ) } } {}
    ?? o { T e → { ^ e } F → {} }
    ^ ( string_from `none` )
}

@ main → i {
    : String b ( pick 1 )
    ( nurl_println ( string_data b ) )
    ^ 0
}

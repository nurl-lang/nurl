// vget_binding_repointed_on_a_back_edge_option_returned: agora #335 — the same, returning the whole option (formal's g4).
// Closed: a take through a binding's `vec_get` slot empties the slot only where no `=` around a loop can have re-pointed the binding (a mutable binding bound outside a loop around the use is copied there instead, __vget_live), and a payload read out of a binding is copied only where that binding owns nothing on the path (__payload_owner_flag; agora #335).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #335: a vec_get binding re-pointed on a loop's back edge, returned whole
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ pick ( Vec String ) ps i k → ?String {
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element of vs long enough for the heap` ) )
    : ~ ? String o ( vec_get [String] vs 0 )
    : ~ i j 0
    ~ < j 2 {
        ? == j k { ^ o } {}
        = o ( vec_get [String] ps 0 )
        = j + j 1
    }
    ^ @ ?String { F }
}

@ main → i {
    : ( Vec String ) qs ( vec_new [String] )
    ( vec_push [String] qs ( string_from `a parameter element long enough for the heap` ) )
    : ?String b ( pick qs 1 )
    ?? b { T s → { ( nurl_println ( string_data s ) ) } F → {} }
    ( nurl_println ( string_data ( vec_at [String] qs 0 ) ) )
    ^ 0
}

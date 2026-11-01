// closure_payload_of_a_captured_vecs_element_returned_twice: agora #335 — a closure returns the payload of a `vec_get` of a Vec it captured by pointer, called twice: the take emptied the enclosing frame's slot, so the second call got none (formal's #1529 c1e).
// Closed: a payload read out of a binding is copied only where that binding owns nothing on the path (__payload_owner_flag); a take through a `vec_get` slot is not made where the Vec is a capture of the closure being compiled (__vget_live, __pl_roots_capture); and an `=` at its binding's own depth replaces the value's lend pairs (mem_note_assign_lend; agora #335).
// main: accepted; ran clean but printed 52 then 0.
// map: §7.6 | A2 | runs-clean | - | agora #335: a closure's vec_get payload of a captured Vec, returned twice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element of the outer vec long enough for the heap` ) )
    : ~ i k 0
    : ( @ String ) f \ → String {
        ? == k 7 { = vs ( vec_new [String] ) } {}
        : ~ ? String o ( vec_get [String] vs 0 )
        ?? o { T e → { ^ e } F → {} }
        ^ ( string_from `none` )
    }
    : String a ( f )
    : String b ( f )
    ( nurl_println_int ( string_len a ) )
    ( nurl_println_int ( string_len b ) )
    ^ 0
}

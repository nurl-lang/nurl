// closure_extends_its_capture_with_a_body_local_vec_of_views: agora #347 — a closure extending a captured Vec with a body-local `( Vec s )` of a body-local String's view: the capture holds a view of what the body frees (r1476_a20).
// Closed: an element read through a pointer into one parameter's buffer and stored through another pointer, for an element type that can hold a view, makes the function copy that parameter's views (g_fn_vcopies, inferred from the pointers' provenance: __note_rawsrc, __note_vcopy); the container it was handed first, or the result, then depends on what they view (agora #347).
// main: accepted; AddressSanitizer reported heap-use-after-free (formal's r1476 review).
// map: §2.11 | A2 | rejected | - | agora #347: a closure extending a captured Vec with a body-local `( Vec s )` of a body-local String's view
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ( @ v ) f \ → v {
        : String b ( string_from `a string freed when the closure returns` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( vec_extend [s] ws t )
    }
    ( f )
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}

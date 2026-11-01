// closure_gives_its_capture_a_clone_of_its_vec_of_views_parameter: agora #347 — a closure giving a captured Vec the `vec_clone` of its `( Vec s )` parameter: the capture holds the views the caller's argument holds, past them (r1476_a22).
// Closed: an element read through a pointer into one parameter's buffer and stored through another pointer, for an element type that can hold a view, makes the function copy that parameter's views (g_fn_vcopies, inferred from the pointers' provenance: __note_rawsrc, __note_vcopy); the container it was handed first, or the result, then depends on what they view (agora #347).
// main: accepted; AddressSanitizer reported heap-use-after-free (formal's r1476 review).
// map: §2.11 | A2 | rejected | - | agora #347: a closure giving a captured Vec the `vec_clone` of its `( Vec s )` parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    : ( @ v ( Vec s ) ) f \ ( Vec s ) pv → v { = ws ( vec_clone [s] pv ) }
    {
        : String b ( string_from `a string freed at the end of its block` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( f t )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}

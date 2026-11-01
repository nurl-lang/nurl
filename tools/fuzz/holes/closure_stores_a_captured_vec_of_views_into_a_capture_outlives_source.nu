// closure_stores_a_captured_vec_of_views_into_a_capture_outlives_source: agora #331 — a closure assigning one captured `( Vec s )` another, which holds a view of a block's String: the String is freed at the block's end and the outer Vec still points into it.
// Closed: a closure's capture or parameter that can hold a view, of any class (a view, an owner of views, a `% Drop` holder, a closure), stored whole into one of its captures stands for what it points into, which the closure cannot see (`cv_`, __clo_cap_marks, agora #331; #312's walk set it for a view only).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #331: a closure giving one capture another capture that owns views
$ `stdlib/core/string.nu`

@ main → i {
    : ~ ( Vec s ) ws ( vec_new [s] )
    ( vec_push [s] ws `first` )
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ~ ( Vec s ) other ( vec_new [s] )
        ( vec_push [s] other ( string_data b ) )
        : ( @ v ) swap \ → v { = ws other }
        ( swap )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}

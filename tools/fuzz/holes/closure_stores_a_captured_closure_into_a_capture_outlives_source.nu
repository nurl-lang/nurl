// closure_stores_a_captured_closure_into_a_capture_outlives_source: agora #331 — a closure assigning one captured closure another, which captures a block's `( Vec D )` of views of a block's String: the String is freed at the block's end, and running the outer closure afterwards reads it.
// Closed: a closure's capture or parameter that can hold a view, of any class (a view, an owner of views, a `% Drop` holder, a closure), stored whole into one of its captures stands for what it points into, which the closure cannot see (`cv_`, __clo_cap_marks, agora #331; #312's walk set it for a view only).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #331: a closure giving one closure capture another that captures a block's Vec of views
$ `stdlib/core/string.nu`

: D { s v }

@ main → i {
    : ~ ( @ v ) g \ → v { ( nurl_println `the outer closure` ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ~ ( Vec D ) ds ( vec_new [D] )
        ( vec_push [D] ds @ D { ( string_data b ) } )
        : ( @ v ) h \ → v { ( nurl_println . ( vec_at [D] ds 0 ) v ) }
        : ( @ v ) swap \ → v { = g h }
        ( swap )
    }
    ( g )
    ^ 0
}

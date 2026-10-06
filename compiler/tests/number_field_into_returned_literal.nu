// number_field_into_returned_literal.nu — a number read out of a local
// struct into the returned literal (`^ @ Ser { y . kd kind . kd spread }`)
// is a copy: kd is dropped on the way out with all it holds.
//
// Counted as the binding the field IS, kd's drop was skipped and its Vec
// leaked per call (packages/anomaly forecast.nu __fc_fit_series). A struct
// with a `% Drop` of its own keeps the skip: a number in it may be a handle
// word its Drop releases.

$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

: Ser { ( Vec f ) y i kind f spread }

@ kind_of ( Vec f ) xs → Ser {
    : ( Vec f ) y ( vec_new [f] )
    ( vec_push [f] y 1.0 )
    ^ @ Ser { y 2 0.5 }
}

@ fit ( Vec f ) xs → Ser {
    : ( Vec f ) y ( vec_zeroed [f] 4 )
    : Ser kd ( kind_of xs )
    ^ @ Ser { y . kd kind . kd spread }
}

unsafe

@ main → i {
    : ( Vec f ) xs ( vec_zeroed [f] 3 )
    : i a0 - ( nurl_alloc_count ) ( nurl_free_count )
    : ~ i k 0
    ~ < k 10 { : Ser s ( fit xs ) = k + k 1 }
    : i a1 - ( nurl_alloc_count ) ( nurl_free_count )
    ( nurl_print `leaked ` ) ( nurl_print_int - a1 a0 ) ( nurl_println `` )
    ^ 0
}

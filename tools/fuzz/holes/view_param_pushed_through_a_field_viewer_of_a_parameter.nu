// view_param_pushed_through_a_field_viewer_of_a_parameter: agora #370 — a callee pushes its view parameter through a field viewer of a struct parameter (agora #397)
// Closed: a view the caller passed (a pv_ parameter) stands for what it points into in the callee's walk, so the callee's answer has the pair h>k and the caller ties the holder argument to the view argument's sources (agora #370).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #370: a callee pushes its view parameter through a field viewer of a struct parameter (agora #397)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { ( Vec s ) kids i n }

@ push_into S o s x → v {
    : ( Vec s ) w . o kids
    ( vec_push [s] w x )
}

@ main → i {
    : S o @ S { ( vec_new [s] ) 1 }
    {
        : String loc ( string_from `a heap string freed at the end of the inner block` )
        ( push_into o ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] . o kids 0 ) )
    ^ 0
}

// should_fail_closure_inout_view.nu
//
// A closure value carries no summary of what it does to an inout
// argument: a view into it ends at the call.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: P { i n ( Vec i ) v }

@ main → i {
    : ~ P q @ P { 0 ( vec_new [i] ) }
    ( vec_push [i] . q v 1 )
    : ( @ v inout P ) g \ inout P p → v { ~ < ( vec_len [i] . p v ) 1000 { ( vec_push [i] . p v 7 ) } }
    : ( Slice i ) sl ( slice_from_vec [i] . q v )
    ( g q )
    ( nurl_println ( nurl_str_int ( slice_at [i] sl 0 ) ) )
    ^ 0
}

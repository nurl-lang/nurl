// should_fail_closure_inout_captured.nu
//
// A closure handed a binding inout that it also captures sees two names
// for one value: the view through the capture dangles after the push.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: P { i n ( Vec i ) v }

@ main → i {
    : ~ P q @ P { 0 ( vec_new [i] ) }
    ( vec_push [i] . q v 1 )
    : ( @ v inout P ) g \ inout P p → v {
        : ( Slice i ) sl ( slice_from_vec [i] . q v )
        ~ < ( vec_len [i] . p v ) 1000 { ( vec_push [i] . p v 7 ) }
        ( nurl_println ( nurl_str_int ( slice_at [i] sl 0 ) ) )
    }
    ( g q )
    ^ 0
}

// diag_closure_inout_captured_after.nu — a binding passed `inout` and,
// after it, a closure argument that captures it: the callee could reach
// one value under two unrelated names.
$ `stdlib/core/vec.nu`

: P { i n ( Vec i ) v }

@ app inout P p ( @ v inout P ) f → v { ( f p ) }

@ main → i {
    : ~ P q @ P { 0 ( vec_new [i] ) }
    : ( @ v inout P ) g \ inout P p → v { ( vec_push [i] . p v ( vec_len [i] . q v ) ) }
    ( app q g )
    ^ 0
}

// should_fail_closure_inout_immutable.nu
//
// An inout closure argument must be a mutable binding, as for a function.
$ `stdlib/core/vec.nu`

: P { i n ( Vec i ) v }

@ main → i {
    : P q @ P { 0 ( vec_new [i] ) }
    : ( @ v inout P ) g \ inout P p → v { = . p n + . p n 1 }
    ( g q )
    ^ 0
}

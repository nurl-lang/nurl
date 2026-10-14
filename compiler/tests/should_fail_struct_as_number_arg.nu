// should_fail_struct_as_number_arg.nu — h269.
//
// A struct passed where a parameter is a number (`( f v )` with a `( Vec
// u )` v and `i x`) compiled to an ill-typed call: the callee read the
// Vec's control-block address as the integer. Rejected now, as the
// reverse (a number where a struct is declared) already was.
$ `stdlib/core/vec.nu`

@ f i x → i { ^ x }

@ main → i {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u 7 )
    ^ ( f v )
}

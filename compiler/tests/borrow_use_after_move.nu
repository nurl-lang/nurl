// Borrow checker — use-after-move regression.
// The harness compiles `borrow_*` tests with --borrowck and records
// the diagnostic in the baseline. `v` is consumed by vec_free, then
// read again by vec_len: a use-after-move. Expect one warning.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 10 )
    ( vec_free [i] v )
    : i n ( vec_len [i] v )
    ( nurl_print ( nurl_str_int n ) )
    ^ 0
}

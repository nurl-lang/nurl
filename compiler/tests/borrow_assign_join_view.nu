// borrow_assign_join_view.nu — a join that hands back a view borrows what
// the view points into, assigned or bound alike.
//
// Each arm is a window into `kb`; `w` is one of them, so it ends with
// `kb`'s block (assign_join_of_fresh_values.nu is the fresh-value side).

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec u ) other ( vec_zeroed [u] 4 )
    : ~ ( Slice u ) w ( slice_from_vec [u] other )
    : b first T
    {
        : ( Vec u ) kb ( vec_zeroed [u] 3 )
        = w ? first ( slice_prefix [u] ( slice_from_vec [u] kb ) 1 ) ( slice_prefix [u] ( slice_from_vec [u] kb ) 2 )
    }
    ^ ( slice_len [u] w )
}

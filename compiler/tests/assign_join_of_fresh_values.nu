// assign_join_of_fresh_values.nu — `= x ? c ( f … ) ( g … )`: a value
// chosen between two fresh results borrows nothing from the views the
// calls were given.
//
// The calls on the line (`slice_from_vec kb`) lend `kb` to whatever takes
// their results directly. For a `:` bound to a join that lending was
// cleared — the arms say what they lend, each by its callee — but an
// assignment kept it: `lo` became a borrow of `kb`, and using `lo` after
// `kb`'s block was refused ("'lo' borrows from 'kb', which ended"). A join
// that does hand back a view still borrows (borrow_assign_join_view.nu).

$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

@ copy_plus ( Slice u ) p i extra → ( Vec u ) {
    : ( Vec u ) out ( slice_to_vec [u] p )
    ( vec_push [u] out # u extra )
    ^ out
}

@ main → i {
    : ~ ( Vec u ) lo ( vec_new [u] )
    : ~ i k 0
    ~ < k 2 {
        : ( Vec u ) kb ( vec_zeroed [u] 3 )
        = lo ? == k 0 ( copy_plus ( slice_from_vec [u] kb ) 1 ) ( copy_plus ( slice_from_vec [u] kb ) 2 )
        = k + k 1
    }
    ( nurl_println ( nurl_str_cat `length ` ( nurl_str_int ( vec_len [u] lo ) ) ) )
    ( nurl_println ( nurl_str_cat `last ` ( nurl_str_int # i ( vec_at [u] lo 3 ) ) ) )
    ^ 0
}

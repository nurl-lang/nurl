// inout_view_param_kept_in_a_second_holder: agora #466 — `@ put inout ( Vec s ) first inout ( Vec s ) h inout s x → v { ( vec_push [s] h x ) }`: the caller's holder kept a view of a String that ends before the holder is read
// main c4d36651: accepted; heap-use-after-free (an inout view parameter stood for nothing in its own walk, so g_fn_vkeeps named no pair).
// map: §2.10 | A2 | rejected | - | agora #466: `@ put inout ( Vec s ) first inout ( Vec s ) h inout s x → v { ( vec_push [s] h x ) }`: the caller's holder kept a view of a String that ends before the holder is read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ put inout ( Vec s ) first inout ( Vec s ) h inout s x → v { ( vec_push [s] h x ) }

@ main → i {
    : ~ ( Vec s ) other ( vec_new [s] )
    : ~ ( Vec s ) hold ( vec_new [s] )
    {
        : String m ( string_from `a heap string long enough to be on the heap for sure` )
        : ~ s x ( string_data m )
        ( put other hold x )
    }
    ( nurl_println ( vec_at [s] hold 0 ) )
    ^ 0
}

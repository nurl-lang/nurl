// view_pushed_through_older_source_borrow_keeps_compiling: agora #292 (precision pin) — a view of a binding declared BEFORE the vector, pushed through `: … w ( id vs )`: the source outlives the vector, so nothing ends (view_pushed_through_older_source_borrow_keeps_compiling).
// Pin: keeping the view in the owner `w` flattens to depends that owner on the source; an older source is no error.
// main: accepted, ran clean.
// map: PushArg | A1 | runs-clean | - | agora #292: a view of an older binding pushed through an identity copy keeps compiling
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ id ( Vec ( Slice u ) ) x → ( Vec ( Slice u ) ) { ^ x }

@ main → i {
    : ( Vec u ) loc ( vec_new [u] )
    ( vec_push_word_u8 loc 42 1 F )
    : ( Vec ( Slice u ) ) vs ( vec_new [( Slice u )] )
    : ( Vec ( Slice u ) ) w ( id vs )
    ( vec_push [( Slice u )] w ( slice_from_vec [u] loc ) )
    ( nurl_println_int # i ( slice_at [u] ( vec_at [( Slice u )] vs 0 ) 0 ) )
    ^ 0
}

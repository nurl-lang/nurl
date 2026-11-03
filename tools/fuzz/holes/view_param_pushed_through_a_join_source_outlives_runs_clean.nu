// view_param_pushed_through_a_join_source_outlives_runs_clean: the join store, read while the viewed String lives.
// The shape the fix must keep.
// main 4d57d596: runs clean.
// map: §2.7 | A2 | runs-clean | - | agora #454: the join store, read while the viewed String lives
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ fill inout ( Vec s ) a inout ( Vec s ) b i c s x → v {
    : ( Vec s ) t ? == c 0 a b
    ( vec_push [s] t x )
}

@ main → i {
    : ~ ( Vec s ) a ( vec_new [s] )
    : ~ ( Vec s ) b ( vec_new [s] )
    : String loc ( string_from `a string that ends first, long enough for heap` )
    {
        ( fill a b 1 ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] b 0 ) )
    ^ 0
}

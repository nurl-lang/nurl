// view_param_pushed_through_an_element_binding_source_outlives_runs_clean: the element-binding store, read while the viewed String lives.
// The shape the fix must keep.
// main 4d57d596: runs clean.
// map: §2.7 | A2 | runs-clean | - | agora #454: the element-binding store, read while the viewed String lives
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ fill ( Vec ( Vec s ) ) vv s x → v {
    : ( Vec s ) e ( vec_at [( Vec s )] vv 0 )
    ( vec_push [s] e x )
}

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    : String loc ( string_from `a string that ends first, long enough for heap` )
    {
        ( fill vv ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] ( vec_at [( Vec s )] vv 0 ) 0 ) )
    ^ 0
}

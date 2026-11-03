// bare_view_popped_off_a_copy_of_a_param_pushed_out: a function handing back a bare view popped off vec_clone of its ( Vec s ) parameter, the view pushed past the string.
// Closed: what a parameter holds, its pseudo `%p`, is views into its caller's storage: a global given them, or another thread, outlives that storage as it outlives a view parameter's own (MEMORY.md §1, §6.5), unless the parameter escapes there whole and its caller is asked; a bare view handed back holding them answers `%k`.
// main 836c0e9: rejected in the callee ("this returns a view of 'c'", the local copy); now answered `%0`, so the caller decides.
// map: §2.8 | A2 | rejected | - | Family G review: a function handing back a bare view popped off vec_clone of its ( Vec s ) parameter, the view pushed past the string
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ first ( Vec s ) v → s {
    : ~ ( Vec s ) c ( vec_clone [s] v )
    ?? ( vec_pop [s] c ) { T x → { ^ x } F → { ^ `` } }
}

@ main → i {
    : ( Vec s ) ws ( vec_new [s] )
    {
        : String b ( string_from `a string freed at the end of its block, long enough` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( vec_push [s] ws ( first t ) )
    }
    ( nurl_println ( vec_at [s] ws 0 ) )
    ^ 0
}

// global_given_a_view_popped_off_a_copy_of_a_param: a string global given a view popped off vec_clone of a ( Vec s ) parameter.
// Closed: what a parameter holds, its pseudo `%p`, is views into its caller's storage: a global given them, or another thread, outlives that storage as it outlives a view parameter's own (MEMORY.md §1, §6.5), unless the parameter escapes there whole and its caller is asked; a bare view handed back holding them answers `%k`.
// main 836c0e9: rejected, as a view of the local copy (a guard: family G's first head accepted it); now named as the parameter's views.
// map: §1 | A2 | rejected | - | Family G review: a string global given a view popped off vec_clone of a ( Vec s ) parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: ~ s g_name `init`

@ keep ( Vec s ) v → v {
    : ~ ( Vec s ) c ( vec_clone [s] v )
    ?? ( vec_pop [s] c ) { T x → { = g_name x } F → {} }
}

@ main → i {
    {
        : String b ( string_from `a string freed at the end of its block, long enough` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data b ) )
        ( keep t )
    }
    ( nurl_println g_name )
    ^ 0
}

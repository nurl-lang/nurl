// thread_given_a_view_popped_off_a_copy_of_a_param: a thread closure capturing a view popped off vec_clone of a ( Vec s ) parameter.
// Closed: what a parameter holds, its pseudo `%p`, is views into its caller's storage: a global given them, or another thread, outlives that storage as it outlives a view parameter's own (MEMORY.md §1, §6.5), unless the parameter escapes there whole and its caller is asked; a bare view handed back holding them answers `%k`.
// main 836c0e9: rejected, as a view of the local copy (a guard: family G's first head accepted it); now named as the parameter's views.
// map: §6.5 | A3 | rejected | - | Family G review: a thread closure capturing a view popped off vec_clone of a ( Vec s ) parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`

@ start ( Vec s ) v → v {
    : ~ ( Vec s ) c ( vec_clone [s] v )
    ?? ( vec_pop [s] c ) {
        T x → {
            : ( @ v ) job \ → v {
                ( sleep_ms 50 )
                ( nurl_println x )
            }
            ?? ( thread_spawn job ) { T th → ( thread_detach th ) F _ → {} }
        }
        F → {}
    }
}

@ main → i {
    {
        : String m ( string_from `a message on the heap, long enough to matter` )
        : ~ ( Vec s ) t ( vec_new [s] )
        ( vec_push [s] t ( string_data m ) )
        ( start t )
    }
    ( sleep_ms 200 )
    ^ 0
}

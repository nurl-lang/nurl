// thread_over_a_closure_capturing_a_vec_param_joined_runs_clean: a function hands a closure over its ( Vec s ) parameter to a thread it joins before returning.
// Kept: what a parameter holds, crossing with the parameter's own value (a closure that captured it), goes as an owner's views do — agora #469's question, as on main; only those views crossing without the owner (a view copied out of it) are refused in the function.
// main 836c0e9: accepted; ran clean.
// map: §6.5 | A3 | runs-clean | - | Family G review: a closure over a ( Vec s ) parameter handed to a thread joined before the function returns
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ serve ( Vec s ) names → v {
    : ( @ v ) job \ → v { ( nurl_println ( vec_at [s] names 0 ) ) }
    ?? ( thread_spawn job ) { T th → { : i _r ( thread_join th ) } F _ → {} }
}

@ main → i {
    : String m ( string_from `a name on the heap, joined before it is freed` )
    : ~ ( Vec s ) t ( vec_new [s] )
    ( vec_push [s] t ( string_data m ) )
    ( serve t )
    ^ 0
}

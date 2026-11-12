// closure_bound_from_vec_at_then_the_vec_swapped_runs_clean: a closure bound from `vec_at`, then the Vec's two closure elements swapped, then the binding called and the Vec freed.
// Guard for agora #593 (#706's root cause): vec_swap reads both elements into bindings and stores them crosswise, declared write-backs (mem_put_back) — a closure element store honours that now, as every other type's does. Before, each store copied its closure (nurl_closure_own_copy): both slots got clones and the two original environments were never released.
// main a25f9b7: accepted, LeakSanitizer: 140 bytes in 6 allocations (nurl_closure_clone).
// map: §7.5 | A2 | runs-clean | - | agora #593 guard: vec_swap over closure elements moves them; a closure bound from vec_at before the swap keeps its own copy, released once
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk sink String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ fill → ( Vec ( @ i i ) ) {
    : ( Vec ( @ i i ) ) fs ( vec_new [( @ i i )] )
    ( vec_push [( @ i i )] fs ( mk ( string_from `four four four four four four` ) ) )
    ( vec_push [( @ i i )] fs ( mk ( string_from `seven chars seven chars seven` ) ) )
    ^ fs
}

@ main → i {
    : ( Vec ( @ i i ) ) fs ( fill )
    : ( @ i i ) f ( vec_at [( @ i i )] fs 0 )
    : b _s ( vec_swap [( @ i i )] fs 0 1 )
    ( nurl_println_int ( f 1 ) )
    ( vec_free [( @ i i )] fs )
    ^ 0
}

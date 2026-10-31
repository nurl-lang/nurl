// nested_closure_effect_lost: a closure that runs a captured closure which grows a Vec did not carry that effect: a view of the Vec stayed live across running the outer closure, and was read after the buffer moved. ASan: heap-use-after-free.
// Closed: a closure body runs the closures it captured, so what those do to their captures is what running it does (their effects are its own: g_clo_caps_now includes what they captured); a view of what they change ends where it runs (h274's walk).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h278 | closure runs a captured closure that grows a Vec; the outer closure's view of it read after
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : ( @ v ) grow \ → v {
        : ~ i k 0
        ~ < k 1000 { ( vec_push [i] v k ) = k + k 1 }
    }
    : ( @ v ) outer \ → v { ( grow ) }
    : ( Slice i ) s ( slice_from_vec [i] v )
    ( outer )
    ( nurl_println_int ( slice_at [i] s 0 ) )
    ^ 0
}

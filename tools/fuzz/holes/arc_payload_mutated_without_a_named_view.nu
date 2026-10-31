// arc_payload_mutated_without_a_named_view: two threads mutated one Arc's payload, unlocked, whenever the mutation did not go through a binding arc_get had bound: `( vec_push ( arc_get a ) x )`, a field of a view, a helper that mutates its parameter, or a String's / a map's mutator (whose summary — writes through raw pointers — closes only after every body). The race check knew only `: v ( arc_get a )` + a container mutator on `v`.
// Closed: every argument's provenance is followed (a view bound or written in place, a field path rooted at one, an Arc handle); a call handing one to a mutated parameter is parked, and after the module a fixed point over the final summaries decides which functions mutate which Arc parameter's payload — a detached closure that does, at any depth and outside a lock, is rejected at the detach.
// main (before this PR): realloc(): invalid old size / ASan double free.
// map: §6.5 | A3 | rejected | h212 | two threads vec_push through arc_get unlocked: data race on payload
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Arc ( Vec i ) ) a ( arc_new [( Vec i )] ( vec_new [i] ) )
    : ( Arc ( Vec i ) ) b ( arc_clone [( Vec i )] a )
    : !Thread ThreadErr r ( thread_spawn \ → v {
        : ~ i k 0
        ~ < k 200000 { ( vec_push [i] ( arc_get [( Vec i )] b ) k ) = k + k 1 }
    } )
    : ~ i k 0
    ~ < k 200000 { ( vec_push [i] ( arc_get [( Vec i )] a ) k ) = k + k 1 }
    ?? r { T t → { ( thread_join t ) } F _ → {} }
    ( nurl_print `len=` ) ( nurl_println_int ( vec_len [i] ( arc_get [( Vec i )] a ) ) )
    ^ 0
}

// opaque_closure_reassigns_a_captured_arc_under_a_payload_slice: a closure body reads a slice out of a captured `: ~ ( Arc ( Vec i ) )`'s payload, then runs a closure parameter that gives the Arc a new value: the old payload was freed under the slice — Arc payload views survive a growth, and the reassignment was not modelled (found fixing agora #644).
// Closed: an opaque closure run inside a closure body (a parameter, or a closure a parameter holds) may be one that captured a `: ~` capture of the body by reference and gives it a new value: such a capture's borrows end there as at a closure that runs here and assigns it, not only its views (bck_opaque_param_run, `@assign`; agora #644).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #644: an opaque closure reassigning a captured mutable Arc under a view of its payload (UAF)
$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/io.nu`

@ main → i {
    : ( Vec i ) v0 ( vec_new [i] )
    ( vec_push [i] v0 41 )
    : ~ ( Arc ( Vec i ) ) mine ( arc_new [( Vec i )] v0 )
    : ( @ v ) reset \ → v { = mine ( arc_new [( Vec i )] ( vec_new [i] ) ) }
    : ( @ v ( @ v ) ) body \ ( @ v ) f → v {
        : ( Slice i ) sl ( slice_from_vec [i] ( arc_get [( Vec i )] mine ) )
        ( f )
        ( nurl_println_int ( slice_at [i] sl 0 ) )
    }
    ( body reset )
    ^ 0
}

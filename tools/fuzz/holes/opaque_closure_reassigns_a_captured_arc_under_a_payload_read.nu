// opaque_closure_reassigns_a_captured_arc_under_a_payload_read: the same with a String read out of a captured `: ~ ( Arc String )`'s payload (found fixing agora #644).
// Closed: an opaque closure run inside a closure body (a parameter, or a closure a parameter holds) may be one that captured a `: ~` capture of the body by reference and gives it a new value: such a capture's borrows end there as at a closure that runs here and assigns it, not only its views (bck_opaque_param_run, `@assign`; agora #644).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #644: an opaque closure reassigning a captured mutable Arc under a String read out of its payload (UAF)
$ `stdlib/std/arc.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

@ main → i {
    : ~ ( Arc String ) mine ( arc_new [String] ( string_from `the first payload, long enough for heap` ) )
    : ( @ v ) reset \ → v { = mine ( arc_new [String] ( string_from `the second payload, long enough for heap` ) ) }
    : ( @ v ( @ v ) ) body \ ( @ v ) f → v {
        : String p ( arc_get [String] mine )
        ( f )
        ( nurl_println ( string_data p ) )
    }
    ( body reset )
    ^ 0
}

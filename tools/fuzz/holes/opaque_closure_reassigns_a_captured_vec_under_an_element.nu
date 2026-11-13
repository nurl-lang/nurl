// opaque_closure_reassigns_a_captured_vec_under_an_element: a closure body binds an element of a captured `: ~ ( Vec String )`, then runs a closure parameter that gives the Vec a new value: the element was freed under the binding — only the views of the capture's buffer ended (found fixing agora #644).
// Closed: an opaque closure run inside a closure body (a parameter, or a closure a parameter holds) may be one that captured a `: ~` capture of the body by reference and gives it a new value: such a capture's borrows end there as at a closure that runs here and assigns it, not only its views (bck_opaque_param_run, `@assign`; agora #644).
// main (before this PR): accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #644: an opaque closure reassigning a captured mutable Vec under an element read out of it (UAF)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

@ main → i {
    : ~ ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs ( string_from `an element string, long enough for heap` ) )
    : ( @ v ) reset \ → v { = vs ( vec_new [String] ) }
    : ( @ v ( @ v ) ) body \ ( @ v ) f → v {
        : String e ( vec_at [String] vs 0 )
        ( f )
        ( nurl_println ( string_data e ) )
    }
    ( body reset )
    ^ 0
}

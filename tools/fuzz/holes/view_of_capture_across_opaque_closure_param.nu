// view_of_capture_across_opaque_closure_param: a closure holds a view of a Vec it captured across a call to one of
// its own closure PARAMETERS; that parameter, chosen by the caller, re-enters
// the closure and grows the Vec, so the view is read after the buffer moved.
// Found modelling the handing of growing closures to calls for the mechanized
// proof (formal/, phase A2); the h274–h280 family. ASan: heap-use-after-free.
// Closed: nurlc carries the effect of running a CAPTURED closure (h278) but
// not of running a PARAMETER, whose captures are the caller's to choose — so
// a call to an opaque closure parameter inside a closure body now ends the
// views of every binding the closure captured by reference, exactly as a call
// that runs a growing closure whose captures are known does (h280). Additive:
// it ends more borrows, never admits more programs (bck_opaque_param_run, the
// `@opaqueclo` sentinel in the borrow walk's pendeff path).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h285 | closure holds a view of a captured Vec across a call to its closure parameter, which re-enters and grows it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f ( @ v ( @ v ) ) g → v {
    : ( @ v ) k \ → v {
        : ( @ v ) noop \ → v {}
        ( g noop )
    }
    ( g k )
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ v ( @ v ) ) grow \ ( @ v ) h → v {
        : ~ i j 0
        ~ < j 400 { ( vec_push [i] v j ) = j + j 1 }
        : ( Slice i ) s ( slice_from_vec [i] v )
        ( h )
        ( nurl_println_int ( slice_at [i] s 0 ) )
    }
    ( f grow )
    ^ 0
}

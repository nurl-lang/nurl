// view_of_capture_across_closure_in_struct_param: a closure holds a view of a Vec it captured across a call to a
// closure a struct PARAMETER holds in a field; that closure, chosen by the
// caller, re-enters the closure and grows the Vec, so the view is read after
// the buffer moved. h285 with the closure parameter behind a field: the h285
// rule looked for a closure parameter and saw a field read. Found checking
// nurlc against the calculus of the mechanized proof (formal/, phase A2); the
// h274–h285 family. ASan: heap-use-after-free.
// Closed: inside a closure body, a call to any closure whose captures are the
// caller's to choose — a closure parameter (h285), or a closure a parameter
// holds: a field, an element, a closure a call handed back; one whose capture
// set has an atom nobody here knows (`?`, `?pK`, __cs_opaque) — ends the views
// of every binding the closure captured by reference (bck_opaque_param_run).
// Additive: it ends more borrows, never admits more programs.
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h286 | h285 with the closure run a field of a struct parameter
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Holder { ( @ v ) cb }

@ f ( @ v Holder ) g → v {
    : ( @ v ) k \ → v {
        : ( @ v ) noop \ → v {}
        ( g @ Holder { noop } )
    }
    ( g @ Holder { k } )
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ v Holder ) grow \ Holder hd → v {
        : ~ i j 0
        ~ < j 400 { ( vec_push [i] v j ) = j + j 1 }
        : ( Slice i ) s ( slice_from_vec [i] v )
        : ( @ v ) h . hd cb
        ( h )
        ( nurl_println_int ( slice_at [i] s 0 ) )
    }
    ( f grow )
    ^ 0
}

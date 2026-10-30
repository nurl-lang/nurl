// view_of_capture_across_closure_in_vec_param: a closure holds a view of a Vec it captured across a call to a
// closure read out of a Vec PARAMETER (vec_at); that closure, chosen by the
// caller, re-enters the closure and grows the captured Vec, so the view is
// read after the buffer moved. h286 with the element in a container: what the
// closure read holds was computed as nothing — vec_at hands the element back
// through a raw pointer, which the capture-set walk does not follow — and the
// generic is compiled after its first use, so the call's answer was not in
// yet. Found checking nurlc against the calculus of the mechanized proof
// (formal/, phase A2); the h274–h286 family. ASan: heap-use-after-free.
// Closed: a closure read through a raw pointer holds anybody's captures (`?`),
// and a closure handed back by a call whose callee is compiled later is
// anybody's until that callee's answer is in (__cs_opaque on a deferred `@N`
// record); either makes the call opaque inside a closure body, which ends the
// views of every binding the closure captured by reference
// (bck_opaque_param_run, as h285 and h286). Additive: it ends more borrows,
// never admits more programs.
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.11 | A2 | rejected | h287 | h285 with the closure run an element of a Vec parameter (vec_at)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ f ( @ v ( Vec ( @ v ) ) ) g → v {
    : ( @ v ) k \ → v {
        : ( @ v ) noop \ → v {}
        : ( Vec ( @ v ) ) ws ( vec_new [( @ v )] )
        ( vec_push [( @ v )] ws noop )
        ( g ws )
    }
    : ( Vec ( @ v ) ) ks ( vec_new [( @ v )] )
    ( vec_push [( @ v )] ks k )
    ( g ks )
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ v ( Vec ( @ v ) ) ) grow \ ( Vec ( @ v ) ) hs → v {
        : ~ i j 0
        ~ < j 400 { ( vec_push [i] v j ) = j + j 1 }
        : ( Slice i ) s ( slice_from_vec [i] v )
        : ( @ v ) h ( vec_at [( @ v )] hs 0 )
        ( h )
        ( nurl_println_int ( slice_at [i] s 0 ) )
    }
    ( f grow )
    ^ 0
}

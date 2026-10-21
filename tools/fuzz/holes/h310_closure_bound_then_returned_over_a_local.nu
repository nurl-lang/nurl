// H310: a closure literal over a local Vec, bound to a name and returned by it (`: f \ … ^ f`), held only a copy of the Vec's handle: the function released the Vec on its way out, and the caller ran the closure on freed memory. (A closure literal written in the return itself takes the Vec over; the bound form did not, and a metamorph control asserted it was fine.)
// Closed: the closure binding holds a handle copy of what it captured by value (h306), and returning it past that binding is rejected as returning any view is, with a message naming the cure.
// main (before this PR): AddressSanitizer reported heap-use-after-free in vec_push, called from the closure.
$ `stdlib/core/vec.nu`

@ caller → ( @ i ) {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 5 )
    : ( @ i ) f \ → i { ( vec_push [i] xs 1 ) ^ ( vec_len [i] xs ) }
    ^ f
}

@ main → i {
    : ( @ i ) g ( caller )
    ( nurl_println_int ( g ) )
    ^ 0
}

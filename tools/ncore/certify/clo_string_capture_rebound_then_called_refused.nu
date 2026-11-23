// closure_literal_capture_given_a_new_value: a closure literal holds a copy of a captured handle (a `: ~` Vec it only reads, captured by value); giving the binding a new value released the Vec the copy still pointed at, and calling the closure read it.
// Closed: a handle a closure literal captures by value is a dependency of the closure (`\\~(…)`, a handle copy `~id`): the binding's value ending — released, given a new value, a field of it replaced — ends the closure. The binding growing, or its elements changing, does not: the closure reads them through the handle when it runs.
// main (before this PR): AddressSanitizer reported heap-use-after-free in vec_at, called from the closure.
// map: §2.11 | A2 | rejected | h306 | a closure literal holds a copy of a captured : ~ Vec's handle; the binding given a new value released it, then the closure ran (UAF)
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ i i ) it \ i k → i { ^ ( vec_at [i] v k ) }
    = v ( vec_new [i] )
    ( vec_push [i] v 9 )
    ( nurl_println_int ( it 0 ) )
    ^ 0
}

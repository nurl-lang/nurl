// returned_closure_argument_replaced_through_inout: h307 for a closure a call returned over its argument (h299): a callee replacing the Vec through `inout` released the one the closure held a copy of the handle of.
// Closed: as h307.
// main (before this PR): AddressSanitizer reported heap-use-after-free in vec_at, called from the closure.
// map: §2.11 | A2 | rejected | h308 | h307 for a closure a call returned over a Vec it captured
$ `stdlib/core/vec.nu`

@ mkit ( Vec i ) v → ( @ i i ) { ^ \ i k → i { ^ ( vec_at [i] v k ) } }

@ reset inout ( Vec i ) v → v { = v ( vec_new [i] ) ( vec_push [i] v 9 ) }

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 7 )
    : ( @ i i ) it ( mkit v )
    ( reset v )
    ( nurl_println_int ( it 0 ) )
    ^ 0
}

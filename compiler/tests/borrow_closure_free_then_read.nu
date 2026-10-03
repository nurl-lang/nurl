// borrow_closure_free_then_read.nu — a closure that frees what it
// captured frees it when it RUNS, not when it is made. Before its first
// use the capture is live (reading it is fine); after a use it may be
// freed, so a read through the captured name — or a second run — is the
// use-after-free.

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) a ( vec_new [i] )
    : ( @ v ) f \ → v { ( vec_free [i] a ) }
    ( nurl_println_int ( vec_len [i] a ) )
    ( f )
    ( nurl_println_int ( vec_len [i] a ) )
    ^ 0
}

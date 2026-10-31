// param_kept_in_result_owner_released: a parameter kept in a callee's result — `: K k ( mk h )` — then read after that owner was released: the result owned the value from the call on, but the borrow walk, unlike a local's ("moved into an owner"), treated the parameter as untouched, so `( kfree k )` released it under the parameter. Found by making TcpConn close itself: a test read its socket after freeing the HTTP/2 frame writer it had handed it to.
// Closed: as h207 — a parameter kept by the callee moves into what keeps it, its result included; a frame that needs the value beside the owner shares or copies it (`( TcpConn_share tcp )`).
// main (before this PR): heap-use-after-free, reading the String `kfree` released.
// map: CallT.sink | A1 | rejected | h208 | param kept in callee result, result freed, then param read
$ `stdlib/core/string.nu`

: H { String s }
: K { H h }

@ mk H h → K { ^ @ K { h } }

@ kfree sink K k → v {}

@ outer H h → v {
    : K k ( mk h )
    ( kfree k )
    ( nurl_print ( string_data . h s ) )
}

@ main → i {
    : H x @ H { ( string_from `hello world, on the heap` ) }
    ( outer x )
    ( nurl_print `\n` )
    ^ 0
}

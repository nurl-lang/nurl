// param_to_keeper_then_read: a parameter handed to a callee that keeps it and releases it itself — `( mid h )`, `mid` binding `( mk h )` and dropping what it bound — then read: the call cleared the parameter's drop flag (the callee keeps it: `@.__nurl_sink.N`), but the borrow walk asked only whether the callee SINKS the argument, so the read after it read what the callee had released. Found by making TcpConn close itself: `__serve_conn` closed the connection its keep-alive loop had already closed.
// Closed: a parameter handed to a callee whose final summary keeps that argument without putting it where the caller still reaches (an escape into the container argument) moves, as one handed to a `sink` does — a local's read after the same call was already "moved into an owner".
// main (before this PR): heap-use-after-free, reading the String `mid` released.
// map: CallT.sink | A1 | rejected | h207 | param handed to callee that keeps and frees it (inferred sink), then read
$ `stdlib/core/string.nu`

: H { String s }
: K { H h }

@ mk H h → K { ^ @ K { h } }

@ mid H h → v {
    : K k ( mk h )
    ( nurl_print ( string_data . . k h s ) )
}

@ outer H h → v {
    ( mid h )
    ( nurl_print ( string_data . h s ) )
}

@ main → i {
    : H x @ H { ( string_from `hello world, on the heap` ) }
    ( outer x )
    ( nurl_print `\n` )
    ^ 0
}

// diag_send_notsend_marker.nu
// The compiler cannot see into an FFI handle: a `sqlite3*` is an `s`,
// a `FILE*` is an `s`, and `s` is Send — neither connection is. That
// is what `% NotSend` is for, and a hand-placed leaf has to propagate
// exactly like a built-in one: here it is reached through a Vec inside
// a struct, two levels from the capture.

$ `stdlib/std/thread.nu`
$ `stdlib/core/marker.nu`
$ `stdlib/core/vec.nu`

: Db { s handle }

% NotSend Db {}

: Pool { ( Vec Db ) conns }

@ main → i {
    : Pool p @ Pool { ( vec_new [Db] ) }
    : ( @ v ) work \ → v { : Pool c p }
    : !Thread ThreadErr r ( thread_spawn work )
    ^ 0
}

// box_struct.nu — Box[T] where T is a multi-field NURL struct.
// Models the Phase 11 DosState shape: heap-stable state struct
// with multiple counters that callers mutate through a stable
// address. The point: a single allocation, multiple call sites
// reading and writing fields through `box_ptr`.

$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`

: Counters {
    i requests
    i errors
    i bytes_in
    i bytes_out
}

@ bump_requests * Counters c → v {
    = . c requests + . c requests 1
}

@ record_io * Counters c i n_in i n_out → v {
    = . c bytes_in + . c bytes_in n_in
    = . c bytes_out + . c bytes_out n_out
}

@ main → i {
    : ( Box Counters ) cb ( box_new [Counters] @ Counters { 0 0 0 0 } )

    // Mutate through box_ptr — the stable address every call site uses.
    : *Counters p ( box_ptr [Counters] cb )
    ( bump_requests p )
    ( bump_requests p )
    ( bump_requests p )
    ( record_io p 1500 240 )
    ( record_io p 800 96 )

    // Read back through the same pointer.
    ( nurl_print `requests=` ) ( nurl_print ( nurl_str_int . p requests ) )
    ( nurl_print ` bytes_in=` ) ( nurl_print ( nurl_str_int . p bytes_in ) )
    ( nurl_print ` bytes_out=` ) ( nurl_print ( nurl_str_int . p bytes_out ) )
    ( nurl_print `\n` )

    // Sanity: box_zero starts every field at 0.
    : ( Box Counters ) cb2 ( box_zero [Counters] )
    : *Counters p2 ( box_ptr [Counters] cb2 )
    ( nurl_print `zero requests=` ) ( nurl_print ( nurl_str_int . p2 requests ) )
    ( nurl_print ` bytes_in=` ) ( nurl_print ( nurl_str_int . p2 bytes_in ) )
    ( nurl_print `\n` )

    ( box_free [Counters] cb )
    ( box_free [Counters] cb2 )
    ( nurl_print `done\n` )
    ^ 0
}

// Negative control for the widened return-escape summary (§2.8). The
// summary now follows a parameter out through a local name, a second
// helper, a nested aggregate and a closure's env — every one of which
// is also how ordinary correct code returns things. These shapes must
// COMPILE, LINK and RUN clean, or the widening bought a diagnostic at
// the price of the no-false-positive property (§6.3):
//
//   1. `id` returns its parameter through a local and `id2` through a
//      second call — legal here because the closure `f` captures a
//      HEAP handle, not a stack binding, so nothing dangles;
//   2. `wrapc` returns a closure that captured its parameter — same,
//      for the same reason;
//   3. `mk2` returns a value parameter inside a NESTED aggregate, the
//      constructor shape that must never be flagged;
//   4. `runit` merely invokes the closure and returns a fresh value, so
//      its result is not a passthrough at all.
$ `stdlib/core/vec.nu`

: Inner { i x }
: Outer { Inner it }

@ id ( @ v ) cb → ( @ v ) {
    : ( @ v ) t cb
    ^ t
}

@ id2 ( @ v ) cb → ( @ v ) {
    ^ ( id cb )
}

@ wrapc ( @ v ) cb → ( @ v ) {
    ^ \ → v { ( cb ) }
}

@ mk2 i a → Outer {
    ^ @ Outer { @ Inner { a } }
}

@ runit ( @ v ) cb → i {
    ( cb )
    ^ 7
}

@ make_counter ( Vec i ) xs → ( @ v ) {
    : ( @ v ) f \ → v { ( vec_push [i] xs 1 ) }
    ^ ( id2 f )
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ( @ v ) bump ( make_counter xs )
    ( bump )
    : ( @ v ) twice ( wrapc bump )
    ( twice )
    : i r ( runit twice )
    : Outer o ( mk2 4 )
    : Inner n . o it
    ( nurl_println_int ( vec_len [i] xs ) )
    ( nurl_println_int + r . n x )
    ( vec_free [i] xs )
    ^ 0
}

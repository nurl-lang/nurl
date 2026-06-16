// Negative control for return-escape inference (§2.8). Two legal
// shapes that must COMPILE, LINK and RUN clean:
//
//   1. `( id f )` — id returns its parameter, so the result IS the
//      stack-reference closure `f`; but it is consumed WITHIN the same
//      frame (bound and invoked), never escaping, so it is fine.
//   2. `^ ( runit f )` — runit takes the stack reference but RETURNS a
//      FRESH value (not its parameter), so the call result is not a
//      stack reference and returning it is legal. (This also pins the
//      fix for a pre-existing false positive: before §2.8, the stale
//      `__last_ident_name__` left by the last argument made
//      `^ ( anycall … stackref )` mis-flag the result as that argument.)
: Counter { i n i max }

@ id ( @ v ) cb → ( @ v ) {
    ^ cb
}

@ runit ( @ v ) cb → i {
    ( cb )
    ^ 0
}

@ use_inscope → i {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    : ( @ v ) g ( id f )
    ( g )
    ( g )
    ^ . c n
}

@ fresh_with_ref → i {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( runit f )
}

@ main → i {
    ( nurl_print_int + ( use_inscope ) ( fresh_with_ref ) )
    ^ 0
}

// Borrow checker — return escape through a CLOSURE CAPTURE
// (docs/MEMORY.md §2.8). `wrapc` returns a closure that captured its
// parameter, so the returned env holds `cb` exactly as a returned
// struct field would hold it. The summary saw `^ p` and `^ @ T { p }`
// but not `^ \ → … p …`, and a parameter is not a stack reference
// inside its own function (its refdepth is 0), so nothing else noticed
// either — `( wrapc f )` handed `caller`'s frame to its caller.
: Counter { i n i max }

@ wrapc ( @ v ) cb → ( @ v ) {
    ^ \ → v { ( cb ) }
}

@ caller → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( wrapc f )
}

@ main → i {
    : ( @ v ) g ( caller )
    ( g )
    ^ 0
}

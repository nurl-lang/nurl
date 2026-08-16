// Borrow checker — return escape through a LOCAL NAME and through a
// second helper (docs/MEMORY.md §2.8). Two spellings of one situation:
//
//   `id`  binds its parameter to a local and returns the local, so the
//         summary's `^ p` test — a bare parameter — did not match;
//   `id2` returns its parameter through `id`, so the passthrough had to
//         compose across a call to be seen at all.
//
// A binding now carries the parameters its initialiser carried
// (`<name>__paramsrc`), and a call result carries the parameters at the
// callee's returned positions, so a reference does not lose its
// provenance by being given a name or by taking one more hop.
: Counter { i n i max }

@ id ( @ v ) cb → ( @ v ) {
    : ( @ v ) t cb
    ^ t
}

@ id2 ( @ v ) cb → ( @ v ) {
    ^ ( id cb )
}

@ caller → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( id2 f )
}

@ main → i {
    : ( @ v ) g ( caller )
    ( g )
    ^ 0
}

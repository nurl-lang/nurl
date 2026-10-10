// OPEN in 0.72.0 — mem_take on a borrowed field claims it: the callee releases a String the caller still holds.
// `peek` binds `b` to `. h name` of its borrowed parameter and calls ( mem_take b ), which makes `b` the
// owner — a primitive for container code, `unsafe`-only by §3.3d but callable here. `b` is released
// when peek returns, and main then prints `. h name` from the released String.
// ASan: heap-use-after-free in _nurl_main (the read of `. h name`; peek is inlined there).
$ `stdlib/core/string.nu`

: Holder { String name }

@ peek Holder h → v {
    : String b . h name
    ( mem_take b )
    ( nurl_println ( string_data b ) )
}

@ main → i {
    : Holder h @ Holder { ( string_from `field` ) }
    ( peek h )
    ( nurl_println ( string_data . h name ) )
    ( nurl_println `ran` )
    ^ 0
}

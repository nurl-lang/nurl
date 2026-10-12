// H200: a local option assigned over an `inout ?T` parameter (`= o l`) was stored as is, and the local still dropped it at scope end: the caller's binding held a string freed under it.
// Closed: an owned local option or result assigned over an `inout` place moves over, as a String or a Vec does — the place's old value is dropped and the local no longer owns it (gen_assign).
// main (before this PR): heap-use-after-free in the caller.
$ `stdlib/core/string.nu`

@ put inout ? String o s x → v {
    : ?String l @ ?String { T ( string_from x ) }
    = o l
}

@ main → i {
    : ~ ? String a @ ?String { F }
    ( put a `the first string, long enough for the heap` )
    ( put a `the second string, long enough for the heap` )
    ?? a { T v → { ( nurl_println ( string_data v ) ) } F → {} }
    ^ 0
}

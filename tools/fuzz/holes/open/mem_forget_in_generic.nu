// OPEN in 0.72.0 — mem_forget in a safe generic function: every instance gives its argument up unreleased.
// `lose [T]` forgets its `sink T` parameter, so lose [String] takes a fresh String and releases nothing.
// mem_forget is `unsafe`-only (§3.3d), but no check rejects it in 0.72.0 (mem_forget_owned_vec); this is
// the generic-instance context a fix must cover too.
// LSan: detected memory leaks — the String (24-byte control block from string_from, and its buffer).
$ `stdlib/core/string.nu`

@ lose [T] sink T x → v { ( mem_forget x ) }

@ main → i {
    ( lose [String] ( string_from `abc` ) )
    ( nurl_println `ran` )
    ^ 0
}

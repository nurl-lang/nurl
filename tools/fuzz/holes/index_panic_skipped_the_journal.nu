// index_panic_skipped_the_journal: a function whose only panic is an index past the end (`vec_at` → nurl_panic_index) leaked its owned bindings when the panic was recovered: the journal's elision took the runtime's index panic for a call that cannot panic, so the function's bindings were never registered for the unwind.
// Closed: the may-panic summary knows the runtime's other panicking entries — nurl_panic_index, a CPU tier's `_missing` gate, the thread crossing's check — as it knows nurl_panic.
// v0.78.0: accepted; LSan reported a leak (the String's control block and buffer).
// map: §7.2 | B | runs-clean | h359 | a function whose only panic is nurl_panic_index had its bindings' journal registrations elided and leaked them under recover: the may-panic summary knows the runtime's panicking entries
$ `stdlib/core/string.nu`
$ `stdlib/std/panic.nu`

@ f ( Vec i ) v i k → i {
    : String s ( string_from `a string long enough to own a heap buffer, surely` )
    : i x ( vec_at [i] v k )
    ( nurl_println ( string_data s ) )
    ^ x
}

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    : !v PanicInfo r ( recover \ → v { : i y ( f v 5 ) } )
    ?? r { T _ → { ( nurl_println `no panic` ) } F e → { ( nurl_println ( string_data . e msg ) ) } }
    ^ 0
}

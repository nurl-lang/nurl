// global_string_from_per_call_owner_leaks: a string module global assigned the result of a call whose ownership is decided per call (a body whose paths disagree — a literal on one, a fresh string on another — or a call compiled after its caller), directly or through a `?` join (`= g ? c ( f n ) `-``), recorded the incoming value as not owned: the fresh string was owned by no one, and every reassignment leaked the one before.
// Closed: the global takes the owner the call's guard slot proves — the slot is emptied, and the global's flag says whether it held the value; a value lent back from the global's own (`= g ( pick g n )`) is the buffer it already owns, kept rather than freed (gen_assign).
// main (before this PR): LeakSanitizer, one string per reassignment.
// Since h273, safe code may not hand a global a string to own at all (another thread could be reading the one the assignment frees), so this probe is rejected; the owning codegen it exercised is covered from `unsafe` code by compiler/tests/owned_string_slot_copies.nu.
// map: §1 | A3 | rejected | h202 | module global given an owned fresh string; now rejected (threads may read global)
$ `stdlib/core/string.nu`

@ label i n → s {
    ? > n 100 { ^ `a literal on this path` } {}
    ^ ( nurl_str_cat3 `a fresh string, ` `long enough for the heap ` ( nurl_str_int n ) )
}

: ~ s g_last `none`

@ remember i n → v { = g_last ( label n ) }

@ remember_join i n → v { = g_last ? < n 50 ( label n ) `small` }

// The global itself on one path, a fresh string on the other.
@ keep_or_extend s cur i n → s {
    ? > n 3 { ^ cur } {}
    ^ ( nurl_str_cat cur `+` )
}

@ step i n → v { = g_last ( keep_or_extend g_last n ) }

@ main → i {
    ( remember 1 )
    ( remember 2 )
    ( remember_join 3 )
    ( remember_join 4 )
    ( nurl_println g_last )
    ( remember 5 )
    ( nurl_println g_last )
    ( step 1 )
    ( step 9 )
    ( step 2 )
    ( nurl_println g_last )
    ^ 0
}

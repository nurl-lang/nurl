// callee_holder_viewing_an_arena_element_after_the_arena_cleared: agora #383 — a callee leaves its Vec of views holding a view of an element of its arena parameter; the caller clears the arena and reads the view
// Closed: a callee's answer has an element pair h>^k for a holder viewing a parameter's elements only (vdi_), and the caller ties the holder to that argument through an element (agora #383).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #383: a callee leaves its Vec of views holding a view of an element of its arena parameter; the caller clears the arena and reads the view
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ put ( Vec String ) arena ( Vec s ) idx String key → v {
    ( vec_push [String] arena key )
    : String e ( vec_at [String] arena - ( vec_len [String] arena ) 1 )
    ( vec_push [s] idx ( string_data e ) )
}

@ main → i {
    : ( Vec String ) arena ( vec_new [String] )
    : ( Vec s ) idx ( vec_new [s] )
    ( put arena idx ( string_from `the first key, long enough for the heap` ) )
    ( vec_clear [String] arena )
    ( nurl_println ( vec_at [s] idx 0 ) )
    ^ 0
}

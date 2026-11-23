// map: §7.6 | A2 | runs-clean | - | AGORA-959: an `inout` String given a copy of a field join keeps it across a later call that may panic
// AGORA-959: the `ak` handover borrows nothing of the struct, so the unwind check sees no view of `p` (claude-formal's precision case)
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ f inout String t → v {
    : P p @ P { ( mk ) 1 }
    : y ? > ( string_len t ) 0 . p s ( mk )
    = t y
    ( string_push_str . p s `more` )
    ( nurl_println ( string_data t ) )
}

@ main → i {
    : ~ String t ( mk )
    ( f t )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}

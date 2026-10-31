// part_cursor_field_store: agora #195 — `= . h s s` into an `inout` struct (part_cursor_field_store).
// Closed: A cursor over part of a local is never that local's whole value (__part_src): the local goes on dropping all of itself, and the cursor's value leaves as a copy where it does not own it (agora #195).
// main: accepted; LeakSanitizer reported a leak.
// map: §7.6 | A2 | runs-clean | h906 | agora #195: `= . h s s` into an `inout` struct
$ `stdlib/core/string.nu`

: W { String s String t }

: H { String s }

@ gets W w → String { ^ . w s }

@ mkw → W { ^ @ W { ( string_from `a string long enough for a heap buffer` ) ( string_from `another string long enough for a heap buffer` ) } }

@ put inout H h → v {
    : W w ( mkw )
    : String s ( gets w )
    = . h s s
}

@ main → i {
    : ~ H h @ H { ( string_from `init` ) }
    ( put h )
    ( nurl_println_int ( string_len . h s ) )
    ^ 0
}

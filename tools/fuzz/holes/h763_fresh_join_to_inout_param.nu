// H763: agora #183 — a `?` of fresh values assigned to an `inout` parameter: the caller's old value (fresh_join_to_inout_param).
// Closed: a `?` / `??` assigned to an `inout` parameter or a by-reference capture measures its arms against the caller's scope — everything the function binds moves out or is copied — and its value is made the caller's own before the old one is dropped (gen_assign; agora #183).
// main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ fill inout String t b c → v { = t ? c ( mk ) ( mk ) }

@ main → i {
    : ~ String t ( mk )
    ( fill t T )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}

// self_join_to_inout_param: agora #183 — an `inout` parameter handed back to itself through a `?` (self_join_to_inout_param).
// Closed: a `?` / `??` assigned to an `inout` parameter or a by-reference capture measures its arms against the caller's scope — everything the function binds moves out or is copied — and its value is made the caller's own before the old one is dropped (gen_assign; agora #183).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h765 | agora #183: an `inout` parameter handed back to itself through a `?`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ fill inout String t b c → v { = t ? c t ( mk ) }

@ main → i {
    : ~ String t ( mk )
    ( fill t T )
    ( fill t F )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}

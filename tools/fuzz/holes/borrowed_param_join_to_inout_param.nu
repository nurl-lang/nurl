// borrowed_param_join_to_inout_param: agora #183 — a borrowed parameter handed through a `?` to an `inout` parameter (borrowed_param_join_to_inout_param).
// Closed: a `?` / `??` assigned to an `inout` parameter or a by-reference capture measures its arms against the caller's scope — everything the function binds moves out or is copied — and its value is made the caller's own before the old one is dropped (gen_assign; agora #183).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h764 | agora #183: a borrowed parameter handed through a `?` to an `inout` parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ fill inout String t String p b c → v { = t ? c p ( mk ) }

@ main → i {
    : ~ String t ( mk )
    : String p ( mk )
    ( fill t p T )
    ( nurl_println_int + ( string_len t ) ( string_len p ) )
    ^ 0
}

// local_field_join_to_inout_param: agora #183 — a local struct's field handed through a `?` to an `inout` parameter (local_field_join_to_inout_param).
// Closed: a `?` / `??` assigned to an `inout` parameter or a by-reference capture measures its arms against the caller's scope — everything the function binds moves out or is copied — and its value is made the caller's own before the old one is dropped (gen_assign; agora #183).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h761 | agora #183: a local struct's field handed through a `?` to an `inout` parameter
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ fill inout String t b c → v {
    ? c {
        : P p @ P { ( mk ) 1 }
        = t ? T . p s ( mk )
    } {}
}

@ main → i {
    : ~ String t ( mk )
    ( fill t T )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}

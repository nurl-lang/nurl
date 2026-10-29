// H762: agora #183 — a closure's local handed through a `?` to a binding it captured by reference (inner_local_join_to_byref_capture).
// Closed: a `?` / `??` assigned to an `inout` parameter or a by-reference capture measures its arms against the caller's scope — everything the function binds moves out or is copied — and its value is made the caller's own before the old one is dropped (gen_assign; agora #183).
// v0.80.0 and main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ String t ( mk )
    : ( @ v ) f \ → v {
        : String x ( mk )
        = t ? T x ( mk )
    }
    ( f )
    ( nurl_println_int ( string_len t ) )
    ^ 0
}

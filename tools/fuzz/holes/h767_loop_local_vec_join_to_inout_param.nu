// H767: agora #183 — a loop body's Vec handed through a `?` to an `inout` parameter (loop_local_vec_join_to_inout_param).
// Closed: a `?` / `??` assigned to an `inout` parameter or a by-reference capture measures its arms against the caller's scope — everything the function binds moves out or is copied — and its value is made the caller's own before the old one is dropped (gen_assign; agora #183).
// main: accepted; AddressSanitizer reported heap-use-after-free.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ fill inout ( Vec String ) v i n → v {
    : ~ i k 0
    ~ < k n {
        : ( Vec String ) w ( vec_new [String] )
        ( vec_push [String] w ( mk ) )
        = v ? > k 0 w ( vec_new [String] )
        = k + k 1
    }
}

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( fill v 3 )
    ( nurl_println_int ( vec_len [String] v ) )
    ^ 0
}

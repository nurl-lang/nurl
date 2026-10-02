// stale_borrow_read_in_mutating_call.nu — a pointer read as an argument of
// the call that mutates its container is not stale: the arguments are read
// before the call runs.
//
// `( vec_push [u] out # u . op k )` copies a byte through `op` into the push
// that may reallocate `out`; the stale-pointer warning fired here because the
// container was marked mutated while its first argument was handled, before
// the second was read (stdlib deflate's back-reference copy). A read after
// the call still warns (should_warn_stale_borrow.nu).

$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec u ) out ( vec_new [u] )
    ( vec_push [u] out # u 7 )
    : ~ i k 0
    ~ < k 5 {
        : *u op ( vec_data [u] out )
        ( vec_push [u] out # u . op k )
        = k + k 1
    }
    ( nurl_print_int ( vec_len [u] out ) ) ( nurl_print `\n` )
    ^ 0
}

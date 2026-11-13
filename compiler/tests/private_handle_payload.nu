// private_handle_payload.nu — a module's handle over its own private type
// is copied and dropped in another file.
//
// private_handle_payload_mod.nu keeps `Impl` private behind
// `pub : H { ( Shared Impl ) ctl }` and writes no `H_drop`. This file never
// names `Impl`. Copying `H` here made the compiler read back the handle's
// recorded type argument, and it judged that as a mention of `Impl` from
// outside the module: `<libh-targ>:1:5: error: private type 'Impl' is not
// visible across files` (AGORA-860).
$ `compiler/tests/private_handle_payload_mod.nu`

: W { H h i k }

// `h` is the caller's: each literal takes a copy of it, made in this file.
@ both H h → i {
    : W a @ W { h 1 }
    : W b @ W { h 2 }
    ^ + + ( h_n . a h ) ( h_n . b h ) + . a k . b k
}

@ main → i {
    : H a ( h_new `x` 7 )
    : i n ( both a )
    : W w @ W { a n }
    ( nurl_println_int + ( h_n . w h ) . w k )
    ^ 0
}

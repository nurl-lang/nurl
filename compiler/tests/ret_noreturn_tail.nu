// ret_noreturn_tail.nu — a value-returning function whose tail is a
// call into a noreturn chain (user panic helper → nurl_exit) is
// COMPLETE: every path either '^'-returns or diverges. The fall-off
// no-value check must not fire (g_fn_noreturn inference: no '^' in the
// helper bodies + diverging tails), and the emitted tail is
// `unreachable`, not a dead `ret undef`. Also covers the infinite-loop
// shape: `~ T` with no break never reaches its exit label.
//
// Expected output:
//   value: 44
//   loop: 3

@ fail_hard s msg → v {
    ( nurl_eprintln msg )
    ( nurl_exit 1 )
}

@ must_be_even i n → i {
    ? == % n 2 0 { ^ * n 2 } {}
    ( fail_hard `odd input` )
}

// The only returns are inside the infinite loop.
@ first_ge i limit → i {
    : ~ i i 0
    ~ T {
        ? >= i limit { ^ i } {}
        = i + i 1
    }
}

@ main → i {
    ( nurl_print `value: ` )
    ( nurl_print ( nurl_str_int ( must_be_even 22 ) ) )
    ( nurl_print `\n` )
    ( nurl_print `loop: ` )
    ( nurl_print ( nurl_str_int ( first_ge 3 ) ) )
    ( nurl_print `\n` )
    ^ 0
}

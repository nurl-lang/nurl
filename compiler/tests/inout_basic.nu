// inout_basic.nu — BORROW.md Phase 4 (Option B): the `inout`
// parameter convention. An `inout` parameter is an exclusive mutable
// borrow — the callee mutates the caller's binding in place. It
// lowers to a `<T>*`-by-address parameter, so a call's effect is
// visible to the caller without returning the modified value.
//
// Exercises a struct `inout`, a scalar `inout`, an `inout` parameter
// alongside an ordinary by-value parameter, and an `inout` re-pass
// (a callee handing its own `inout` parameter on to another).

: Counter { i n  i max }

// Struct inout: mutate a field of the caller's Counter.
@ bump inout Counter c → v {
    = . c n + . c n 1
}

// inout beside an ordinary by-value parameter.
@ bump_by inout Counter c  i d → v {
    = . c n + . c n d
}

// inout re-pass: `c` is this function's own inout parameter, handed
// straight on to `bump` — the address flows through unchanged.
@ bump_twice inout Counter c → v {
    ( bump c )
    ( bump c )
}

// Scalar inout: replaces the old `*i` mutation idiom.
@ add100 inout i x → v {
    = x + x 100
}

@ main → i {
    : ~ Counter c @ Counter { 0 10 }
    ( bump c )                  // n = 1
    ( bump_by c 5 )             // n = 6
    ( bump_twice c )            // n = 8
    : ~ i k 7
    ( add100 k )                // k = 107
    ( nurl_print `c.n=` ) ( nurl_print ( nurl_str_int . c n ) ) ( nurl_print `\n` )
    ( nurl_print `k=` ) ( nurl_print ( nurl_str_int k ) ) ( nurl_print `\n` )
    ^ 0
}

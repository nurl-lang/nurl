// OPEN in 0.72.0 — a `sink s` callee that panics: the unwind releases a literal the caller passed.
// `take` panics when n = 0, under recover. The unwind journal reclaims the `sink s` argument — right for
// the owned `m` in the first closure, but the second closure passes a literal and the drain frees static
// memory. The last call (no panic) hands a temporary to the same `sink s`, which only reads it: it leaks.
// ASan: SEGV in the allocator (free of the literal) under nurl__jrnl_drain <- nurl_panic <- the recover closure.
$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

@ take sink s x i n → i {
    ? == n 0 { ( panic `boom` ) } {}
    ^ ( strlen x )
}

@ main → i {
    : !v PanicInfo r1 ( recover \ → v { : s m ( nurl_str_cat `ab` `cd` ) ( nurl_println_int ( take m 0 ) ) } )
    ?? r1 { T _ → {} F p → ( panic_info_free p ) }
    : !v PanicInfo r2 ( recover \ → v { ( nurl_println_int ( take `lit` 0 ) ) } )
    ?? r2 { T _ → {} F p → ( panic_info_free p ) }
    ( nurl_println_int ( take ( nurl_str_cat `x` `y` ) 1 ) )
    ^ 0
}

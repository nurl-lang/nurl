// OPEN in 0.72.0 — a borrowed raw string parameter handed to string_adopt: the callee takes over whatever it is passed.
// `via` adopts its `s p` always, `sometimes` only when `c` is true, and both are inferred to consume
// their argument. A literal argument is adopted and released as if it were heap memory; an owned
// string passed to `sometimes` on the path that does not adopt it is given up by the caller and
// released by nobody (`m2` leaks). The probe faults at the first literal.
// ASan: SEGV in the allocator's Deallocate (free of the literal `lit`, static memory), from nurl_vec_drop.
$ `stdlib/core/string.nu`

@ via s p → i { ^ ( string_len ( string_adopt p ) ) }

@ sometimes s x b c → i { ? c { : String t ( string_adopt x ) ^ ( string_len t ) } {} ^ 0 }

@ main → i {
    : s m ( nurl_str_cat `ab` `cd` )
    ( nurl_println_int ( via m ) )
    ( nurl_println_int ( via `lit` ) )
    : s m2 ( nurl_str_cat `ab` `cd` )
    ( nurl_println_int ( sometimes m2 F ) )
    ( nurl_println_int ( sometimes `lit` T ) )
    ^ 0
}

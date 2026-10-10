// OPEN in 0.72.0 — a closure's raw string parameter handed to string_adopt: the closure frees what the caller owns.
// Closure parameters are borrowed, so main keeps `m` after ( f m ) — but the closure adopted `m` and
// released it, and main's ( nurl_println m ) reads freed memory; ( f `lit` ) adopts a literal and
// releases static memory. The literal comes first and faults first.
// ASan: SEGV in the allocator's Deallocate (free of the literal `lit`), from nurl_vec_drop.
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ i s ) f \ s x → i { : String t ( string_adopt x ) ^ ( string_len t ) }
    : s m ( nurl_str_cat `ab` `cd` )
    ( nurl_println_int + ( f m ) ( f `lit` ) )
    ( nurl_println m )
    ^ 0
}

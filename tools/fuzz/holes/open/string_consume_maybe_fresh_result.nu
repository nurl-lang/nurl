// OPEN in 0.72.0 — a call result that is fresh on one path and a literal on the other, handed to string_adopt.
// `mk` returns ( nurl_str_cat `a` `b` ) when `c` is true and the literal `lit` otherwise, so
// ( string_adopt ( mk F ) ) adopts the literal and releases static memory at scope exit. The `take`
// lines hand the same maybe-literal results to a `sink s` (one on a path not taken): shapes a fix
// must also hold.
// ASan: SEGV in the allocator's Deallocate (free of the literal), from nurl_vec_drop in main.
$ `stdlib/core/string.nu`

@ take sink s x → i { ^ ( strlen x ) }

@ mk b c → s { ? c { ^ ( nurl_str_cat `a` `b` ) } {} ^ `lit` }

@ main → i {
    : String a ( string_adopt ( mk F ) )
    : s m ( mk T )
    ? > ( string_len a ) 100 { ( nurl_println_int ( take m ) ) } {}
    : s m2 ( mk F )
    ( nurl_println_int + ( take m2 ) ( take ( mk F ) ) )
    ^ 0
}

// string_consume_maybe_fresh_result: a call result that is fresh on one path and a literal on the other, handed to string_adopt.
// Closed: in safe code only a declared `sink` takes a raw string over, and its callee releases it; a caller hands over a string it owns, or a copy of anything else (mem_sink_str_arg, __own_sink_str_params).
// `mk` returns ( nurl_str_cat `a` `b` ) when `c` is true and the literal `lit` otherwise, so
// ( string_adopt ( mk F ) ) adopts the literal and releases static memory at scope exit. The `take`
// lines hand the same maybe-literal results to a `sink s` (one on a path not taken): shapes a fix
// must also hold.
// ASan: SEGV in the allocator's Deallocate (free of the literal), from nurl_vec_drop in main.
// map: CallT.summary | A1 | runs-clean | h166 | result fresh on one path, literal on other, adopted and freed
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

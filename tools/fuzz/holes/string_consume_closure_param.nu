// string_consume_closure_param: a closure's raw string parameter handed to string_adopt: the closure frees what the caller owns.
// Closed: in safe code only a declared `sink` takes a raw string over, and its callee releases it; a caller hands over a string it owns, or a copy of anything else (mem_sink_str_arg, __own_sink_str_params).
// Closure parameters are borrowed, so main keeps `m` after ( f m ) — but the closure adopted `m` and
// released it, and main's ( nurl_println m ) reads freed memory; ( f `lit` ) adopts a literal and
// releases static memory. The literal comes first and faults first.
// ASan: SEGV in the allocator's Deallocate (free of the literal `lit`), from nurl_vec_drop.
// map: §2.11 | A2 | runs-clean | h162 | closure's borrowed s param adopted; caller's string/literal freed
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ i s ) f \ s x → i { : String t ( string_adopt x ) ^ ( string_len t ) }
    : s m ( nurl_str_cat `ab` `cd` )
    ( nurl_println_int + ( f m ) ( f `lit` ) )
    ( nurl_println m )
    ^ 0
}

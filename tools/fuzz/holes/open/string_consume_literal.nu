// OPEN in 0.72.0 — a string literal handed to string_adopt is taken over as heap memory and released.
// ( string_adopt `literal` ) builds a String around static memory, and its release at scope exit frees it.
// The `take` calls hand a bound and a direct literal to a `sink s` parameter: harmless while a `sink s`
// callee never releases (string_consume_sink_param_only_read), they hold a fix to never freeing a literal.
// ASan: SEGV in the allocator's Deallocate (free of static memory), from nurl_vec_drop in main.
$ `stdlib/core/string.nu`

@ take sink s x → i { ^ ( strlen x ) }

@ main → i {
    : String a ( string_adopt `literal` )
    : s lit `bound literal`
    ( nurl_println_int + ( string_len a ) ( take lit ) )
    ( nurl_println_int ( take `direct` ) )
    ^ 0
}

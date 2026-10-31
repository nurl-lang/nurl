// string_consume_literal: a string literal handed to string_adopt is taken over as heap memory and released.
// Closed: in safe code only a declared `sink` takes a raw string over, and its callee releases it; a caller hands over a string it owns, or a copy of anything else (mem_sink_str_arg, __own_sink_str_params).
// ( string_adopt `literal` ) builds a String around static memory, and its release at scope exit frees it.
// The `take` calls hand a bound and a direct literal to a `sink s` parameter: harmless while a `sink s`
// callee never releases (string_consume_sink_param_only_read), they hold a fix to never freeing a literal.
// ASan: SEGV in the allocator's Deallocate (free of static memory), from nurl_vec_drop in main.
// map: CallT.sink | A1 | runs-clean | h165 | string literal handed to string_adopt, freed as heap
$ `stdlib/core/string.nu`

@ take sink s x → i { ^ ( strlen x ) }

@ main → i {
    : String a ( string_adopt `literal` )
    : s lit `bound literal`
    ( nurl_println_int + ( string_len a ) ( take lit ) )
    ( nurl_println_int ( take `direct` ) )
    ^ 0
}

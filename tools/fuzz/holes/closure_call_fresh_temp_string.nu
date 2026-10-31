// closure_call_fresh_temp_string: a fresh string handed straight to a call of a closure value is never released.
// Closed: a fresh string handed to a call of a closure value is released once the call returns (gen_call).
// `f` is a closure value with a raw string parameter, called with the temporary ( nurl_str_cat `x` `y` ).
// A call of a named function releases such a temporary once it returns; a call through a closure
// value does not, and the closure only reads its parameter, so nobody releases it.
// LSan: detected memory leaks — 3 bytes (the "xy" buffer), allocated in main.
// map: §7.5 | A2 | runs-clean | h145 | fresh temp string passed to closure-value call never released
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ i s ) f \ s x → i { ^ ( strlen x ) }
    ( nurl_println_int ( f ( nurl_str_cat `x` `y` ) ) )
    ( nurl_println `CLOSURE-TEMP-MARK` )
    ^ 0
}

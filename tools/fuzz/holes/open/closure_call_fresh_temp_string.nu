// OPEN in 0.72.0 — a fresh string handed straight to a call of a closure value is never released.
// `f` is a closure value with a raw string parameter, called with the temporary ( nurl_str_cat `x` `y` ).
// A call of a named function releases such a temporary once it returns; a call through a closure
// value does not, and the closure only reads its parameter, so nobody releases it.
// LSan: detected memory leaks — 3 bytes (the "xy" buffer), allocated in main.
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ i s ) f \ s x → i { ^ ( strlen x ) }
    ( nurl_println_int ( f ( nurl_str_cat `x` `y` ) ) )
    ( nurl_println `CLOSURE-TEMP-MARK` )
    ^ 0
}

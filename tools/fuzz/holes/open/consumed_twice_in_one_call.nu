// OPEN in 0.72.0 — the same String passed to a `sink` parameter and to a borrowed one of a single call.
// ( f m m ): `x` takes `m` over and `f` releases it with string_free, then reads `y` — the same String.
// A name moved by an earlier argument of the same call is not reported when a later argument reads it.
// ASan: heap-use-after-free in main (f inlined): string_len of `y` reads the String string_free released.
$ `stdlib/core/string.nu`

@ f sink String x String y → i { : i n ( string_len x ) ( string_free x ) ^ + n ( string_len y ) }

@ main → i {
    : String m ( string_from `abcd` )
    ( nurl_println_int ( f m m ) )
    ( nurl_println `P2B-MARK` )
    ^ 0
}

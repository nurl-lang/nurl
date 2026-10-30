// closure_from_a_call_outlives_its_argument: a closure a call hands back, over an argument the callee captured without taking it over, outlived that argument: the caller released the String, then called the closure, which read the freed buffer.
// Closed: what a returned closure lends (the callee's `retclo` summary) is a source of the call's result in the borrow walk (bck_sx_ev), so the binding holds a view of the argument and the release ends it. Returning such a closure past its argument was already rejected (gen_ret); keeping it past one was not.
// main (before this PR): AddressSanitizer reported heap-use-after-free in the closure's string_len.
// map: §2.11 | A2 | rejected | h299 | a closure a call returned over an argument it captured without taking it over (retclo) stayed usable after the caller released the argument (UAF)
$ `stdlib/core/string.nu`

@ mkc String a → ( @ i ) { ^ \ → i { ^ ( string_len a ) } }

@ main → i {
    : String x ( string_from `abcd` )
    : ( @ i ) f ( mkc x )
    ( string_free x )
    ( nurl_println_int ( f ) )
    ^ 0
}

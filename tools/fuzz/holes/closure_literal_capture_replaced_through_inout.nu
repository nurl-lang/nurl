// closure_literal_capture_replaced_through_inout: h306 through an `inout` parameter: a callee that gives its `inout` String a new value released the one a closure literal had captured by value, and calling the closure read it. A call that may replace the value counted only as one that may drop what it holds, which ends views into it but not a copy of its handle.
// Closed: a call whose callee may give an `inout` parameter (or an owned field of one) a new value (g_fn_replaces) ends everything that depends on the argument, a handle copy too.
// main (before this PR): AddressSanitizer reported heap-use-after-free in the closure's string_len.
// map: §2.11 | A2 | rejected | h307 | h306 through an inout callee replacing the captured String
$ `stdlib/core/string.nu`

@ fresh inout String s → v { = s ( string_from `new` ) }

@ main → i {
    : ~ String t ( string_from `old` )
    : ( @ i ) f \ → i { ^ ( string_len t ) }
    ( fresh t )
    ( nurl_println_int ( f ) )
    ^ 0
}

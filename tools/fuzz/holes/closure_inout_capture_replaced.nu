// closure_inout_capture_replaced: a closure that hands a captured `: ~` binding to an `inout` parameter took the binding by value: the callee replaced the closure's copy — a String given a new one released the buffer the caller's binding still held (heap-use-after-free), and a number's write was lost.
// Closed: a binding a closure hands to an `inout` parameter is captured by pointer, as one it assigns is (__clo_scan_inout_call); a capture taken by value is as mutable as its binding, so an immutable one cannot reach an `inout` parameter either.
// main (before this PR): AddressSanitizer reported heap-use-after-free printing the String.
// map: §2.4 | A2 | runs-clean | h298 | a closure handing a captured : ~ String to an inout parameter took it by value; the callee replaced the copy and released the caller's buffer (UAF)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ fresh inout String s → v { = s ( string_from `new` ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 ) ( vec_push [i] xs 2 )
    : ~ String t ( string_from `old` )
    ( vec_each [i] xs \ i x → v { ( fresh t ) } )
    ( nurl_println ( string_data t ) )
    ^ 0
}

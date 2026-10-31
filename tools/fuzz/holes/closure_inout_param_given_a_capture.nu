// closure_inout_param_given_a_capture: a closure's `inout` parameter given one of the closure's captures (`\ inout String y → v { = y b }`) stored the captured buffer as is: the caller's binding and `b` both owned it, and the value the parameter held leaked.
// Closed: the capture is copied in, as any binding that does not own its value is (h345), and the value the parameter held is dropped.
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h346 | a closure's inout parameter given one of the closure's captures stored the captured buffer as is; a capture is copied in like any binding whose value another owner keeps
$ `stdlib/core/string.nu`

@ apply ( @ v inout String ) f inout String x → v { ( f x ) }

@ main → i {
    : String b ( string_from `a captured string long enough to own a buffer` )
    : ~ String x ( string_from `the old value, long enough to own a buffer too` )
    ( apply \ inout String y → v { = y b } x )
    ( nurl_println ( string_data x ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}

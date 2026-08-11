// diag_closure_body_unclosed.nu — a closure literal whose body '{' is
// never closed. The capture pre-scan (simple_capture_analysis) walks
// the body before it is parsed and had no EOF guard — this shape hung
// the compiler. Now a hard error anchored at the closure's '{'.

@ main → i {
    : ( @ v ) f \ → v { ( nurl_print `x` )
        ( f )
        ^ 0

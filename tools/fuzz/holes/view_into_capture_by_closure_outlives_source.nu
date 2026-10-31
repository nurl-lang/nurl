// view_into_capture_by_closure_outlives_source: agora #259 — a closure assigning a by-reference capture a view of another capture, read after that one ended (view_into_capture_by_closure_outlives_source).
// Closed: a view a callee stores into an `inout` argument (a whole assignment in its last statement, or a field of a struct of views; the argument at any position) and a view a closure gives one of its captures are dependencies of that argument or capture, where the call or the closure runs (mem_rawlit_unclaimed at the body's end, an `inout` struct of views as the keeping container, the closure effect `@vp=`; agora #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #259: a closure assigning a by-reference capture a view of another capture, read after that one ended
$ `stdlib/core/string.nu`

: V { s v }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ V w @ V { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        : ( @ v ) repoint \ → v { = w @ V { ( string_data b ) } }
        ( repoint )
    }
    ( nurl_println . w v )
    ^ 0
}

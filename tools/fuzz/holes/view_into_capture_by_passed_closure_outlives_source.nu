// view_into_capture_by_passed_closure_outlives_source: agora #259 — a closure literal handed to a function that runs it, assigning a by-reference capture a view of a block-local String (view_into_capture_by_passed_closure_outlives_source).
// Closed: a view a callee stores into an `inout` argument (a whole assignment in its last statement, or a field of a struct of views; the argument at any position) and a view a closure gives one of its captures are dependencies of that argument or capture, where the call or the closure runs (mem_rawlit_unclaimed at the body's end, an `inout` struct of views as the keeping container, the closure effect `@vp=`; agora #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.11 | A2 | rejected | - | agora #259: a closure literal handed to a function that runs it, assigning a by-reference capture a view of a block-local String
$ `stdlib/core/string.nu`

: V { s v }

@ run_it ( @ v ) f → v { ( f ) }

@ main → i {
    : String a ( string_from `the outer string` )
    : ~ V w @ V { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( run_it \ → v { = w @ V { ( string_data b ) } } )
    }
    ( nurl_println . w v )
    ^ 0
}

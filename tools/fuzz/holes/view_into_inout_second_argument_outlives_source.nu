// view_into_inout_second_argument_outlives_source: agora #259 — the same with the `inout` struct of views the callee's second parameter (view_into_inout_second_argument_outlives_source).
// Closed: a view a callee stores into an `inout` argument (a whole assignment in its last statement, or a field of a struct of views; the argument at any position) is a dependency of that argument where the call runs (mem_rawlit_unclaimed at the body's end, an `inout` struct of views as the keeping container; agora #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #259: the same with the `inout` struct of views the callee's second parameter
$ `stdlib/core/string.nu`

: V { s v }

@ point s v inout V w → v { = w @ V { v } }

@ main → i {
    : String a ( string_from `the outer string` )
    : ~ V w @ V { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( point ( string_data b ) w )
    }
    ( nurl_println . w v )
    ^ 0
}

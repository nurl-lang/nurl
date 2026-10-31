// view_into_inout_assign_then_more_outlives_source: agora #259 — the same with the assignment followed by another statement in the callee (view_into_inout_assign_then_more_outlives_source).
// Closed: a view a callee stores into an `inout` argument (a whole assignment in its last statement, or a field of a struct of views; the argument at any position) and a view a closure gives one of its captures are dependencies of that argument or capture, where the call or the closure runs (mem_rawlit_unclaimed at the body's end, an `inout` struct of views as the keeping container, the closure effect `@vp=`; agora #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #259: the same with the assignment followed by another statement in the callee
$ `stdlib/core/string.nu`

: V { s v }

@ point inout V w s v → v {
    = w @ V { v }
    ( nurl_println `pointed` )
}

@ main → i {
    : String a ( string_from `the outer string` )
    : ~ V w @ V { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( point w ( string_data b ) )
    }
    ( nurl_println . w v )
    ^ 0
}

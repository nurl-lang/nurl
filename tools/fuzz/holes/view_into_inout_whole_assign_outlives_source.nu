// view_into_inout_whole_assign_outlives_source: agora #259 — a struct of views given a view of a block-local String by an `inout` callee that assigns its whole parameter, read after the block (view_into_inout_whole_assign_outlives_source).
// Closed: a view a callee stores into an `inout` argument (a whole assignment in its last statement, or a field of a struct of views; the argument at any position) is a dependency of that argument where the call runs (mem_rawlit_unclaimed at the body's end, an `inout` struct of views as the keeping container; agora #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #259: a struct of views given a view of a block-local String by an `inout` callee that assigns its whole parameter, read after the block
$ `stdlib/core/string.nu`

: V { s v }

@ point inout V w s v → v { = w @ V { v } }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ V w @ V { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( point w ( string_data b ) )
    }
    ( nurl_println . w v )
    ^ 0
}

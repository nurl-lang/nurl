// drop_holder_given_younger_view_through_inout: agora #259 — a `% Drop` holder given a view of a younger String by an `inout` callee (drop_holder_given_younger_view_through_inout).
// Closed: a view a callee stores into an `inout` argument (a whole assignment in its last statement, or a field of a struct of views; the argument at any position) is a dependency of that argument where the call runs (mem_rawlit_unclaimed at the body's end, an `inout` struct of views as the keeping container; agora #259).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.14 | A2 | rejected | - | agora #259: a `% Drop` holder given a view of a younger String by an `inout` callee
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ point inout W w s v → v { = w @ W { v } }

@ main → i {
    : String a ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { ( string_data a ) }
    {
        : String b ( string_from `the inner string, freed at the end of its block` )
        ( point w ( string_data b ) )
    }
    ^ 0
}

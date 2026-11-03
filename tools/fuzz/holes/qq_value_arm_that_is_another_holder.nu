// qq_value_arm_that_is_another_holder: agora #416 — `= a ?? o { T m → @ W { `lit` } F → b }` with b a holder of a block local's view
// Closed: a `??` value's arm is taken by its operand, as a `?` arm is — a bare binding by its name, so what it holds and views goes with the join; a literal by none (agora #416).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #416: `= a ?? o { T m → @ W { `lit` } F → b }` with b a holder of a block local's view
$ `stdlib/core/string.nu`

: W { s v }

@ main → i {
    : ~ W a @ W { `x` }
    : ?i o @ ?i { F }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : W b @ W { ( string_data t ) }
        = a ?? o { T m → @ W { `lit` } F → b }
    }
    ( nurl_println . a v )
    ^ 0
}

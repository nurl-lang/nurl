// qq_value_arm_that_is_a_holder_binding: agora #416 — `= a ?? o { T m → @ W { `lit` } F → a }`, a holding a view of a block local
// Closed: a `??` value's arm is taken by its operand, as a `?` arm is — a bare binding by its name, so what it holds and views goes with the join; a literal by none (agora #416).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #416: `= a ?? o { T m → @ W { `lit` } F → a }`, a holding a view of a block local
$ `stdlib/core/string.nu`

: W { s v }

@ main → i {
    : ~ W a @ W { `x` }
    : ?i o @ ?i { F }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        = a @ W { ( string_data t ) }
        = a ?? o { T m → @ W { `lit` } F → a }
    }
    ( nurl_println . a v )
    ^ 0
}

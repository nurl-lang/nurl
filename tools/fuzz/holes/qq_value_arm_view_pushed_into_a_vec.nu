// qq_value_arm_view_pushed_into_a_vec: agora #416 — `( vec_push [s] hs ?? o { T m → `lit` F → b } )` with b a view of a block local
// Closed: a `??` value's arm is taken by its operand, as a `?` arm is — a bare binding by its name, so what it holds and views goes with the join; a literal by none (agora #416).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #416: `( vec_push [s] hs ?? o { T m → `lit` F → b } )` with b a view of a block local
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec s ) hs ( vec_new [s] )
    : ?i o @ ?i { F }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : s b ( string_data t )
        ( vec_push [s] hs ?? o { T m → `lit` F → b } )
    }
    ?? ( vec_get [s] hs 0 ) { T v → ( nurl_println v ) F → {} }
    ^ 0
}

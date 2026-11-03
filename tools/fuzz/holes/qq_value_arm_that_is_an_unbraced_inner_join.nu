// qq_value_arm_that_is_an_unbraced_inner_join: agora #452 — `= a ?? o { T m → @ W { `lit` } F → ?? o2 { T k → @ W { `l2` } F → b } }`, b viewing a block local
// Closed: a `??` that is an outer join's whole arm publishes its source expression — its arms joined — as a value `??` does, so the outer arm is taken by it (gen_match m_sxv; agora #452).
// main: heap-use-after-free (base 4df9b050 too).
// map: §7.6 | A2 | rejected | - | agora #452: `= a ?? o { T m → @ W { `lit` } F → ?? o2 { T k → @ W { `l2` } F → b } }`, b viewing a block local
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { ( Vec s ) vs }
: Q { String name s view }
: PQ { Q q }

@ main → i {
    : ~ W a @ W { `x` }
    : ?i o @ ?i { F }
    : ?i o2 @ ?i { F }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : W b @ W { ( string_data t ) }
        = a ?? o { T m → @ W { `lit` } F → ?? o2 { T k → @ W { `l2` } F → b } }
    }
    ( nurl_println . a v )
    ^ 0
}

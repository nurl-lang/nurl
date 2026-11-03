// qq_value_arm_struct_field_after_a_nested_read: agora #416 — a struct field arm `. p q`, after `. . pq q view` of a holder viewing a block local was read
// Guard: a `??` field arm is taken by its own member path, not one a read elsewhere left behind (agora #416).
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #416: a struct field arm `. p q`, after `. . pq q view` of a holder viewing a block local was read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { ( Vec s ) vs }
: Q { String name s view }
: PQ { Q q }

@ main → i {
    : ?i o @ ?i { F }
    : ~ Q r @ Q { ( string_from `start` ) `x` }
    : ~ PQ p @ PQ { @ Q { ( string_from `p name` ) `static` } }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : PQ pq @ PQ { @ Q { ( string_from `q name` ) ( string_data t ) } }
        ( nurl_println . . pq q view )
        : s z . . pq q view
        = r ?? o { T m → @ Q { ( string_from `lit` ) `lit` } F → . p q }
    }
    ( nurl_println . r view )
    ^ 0
}

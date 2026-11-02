// qq_value_arm_vec_field_of_a_block_local_holder: agora #416 — `= r ?? o { T m → ( vec_new [s] ) F → . p vs }` with p's ( Vec s ) field viewing a block local
// Closed: a `??` arm that reads a field records its member path, as a `?` arm does, and is taken by that path (__sx_froot; agora #416).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | rejected | - | agora #416: `= r ?? o { T m → ( vec_new [s] ) F → . p vs }` with p's ( Vec s ) field viewing a block local
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { ( Vec s ) vs }
: Q { String name s view }
: PQ { Q q }

@ main → i {
    : ~ ( Vec s ) r ( vec_new [s] )
    : ?i o @ ?i { F }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : ~ ( Vec s ) hv ( vec_new [s] )
        ( vec_push [s] hv ( string_data t ) )
        : ~ P p @ P { hv }
        = r ?? o { T m → ( vec_new [s] ) F → . p vs }
    }
    ?? ( vec_get [s] r 0 ) { T v → ( nurl_println v ) F → {} }
    ^ 0
}

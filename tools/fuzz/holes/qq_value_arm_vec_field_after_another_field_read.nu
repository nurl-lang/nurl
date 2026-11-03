// qq_value_arm_vec_field_after_another_field_read: agora #416 — as qq_value_arm_vec_field_of_a_block_local_holder, after another struct's field was read
// Closed: a `??` arm that reads a field records its member path, as a `?` arm does, and is taken by that path (__sx_froot; agora #416).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | rejected | - | agora #416: as qq_value_arm_vec_field_of_a_block_local_holder, after another struct's field was read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { ( Vec s ) vs }

@ main → i {
    : ~ ( Vec s ) r ( vec_new [s] )
    : ?i o @ ?i { F }
    : ~ P q @ P { ( vec_new [s] ) }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : ~ P p @ P { ( vec_new [s] ) }
        ( vec_push [s] . p vs ( string_data t ) )
        ( vec_push [s] . q vs `static` )
        = r ?? o { T m → ( vec_new [s] ) F → . p vs }
    }
    ?? ( vec_get [s] r 0 ) { T v → ( nurl_println v ) F → {} }
    ^ 0
}

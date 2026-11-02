// qq_value_arm_vec_field_of_a_block_local_after_another_holders_read: agora #416 — `F → . p vs` of a block-local holder of statics, copied out, after `. q vs` of a holder viewing a block local was read
// Guard: a `??` field arm is taken by its own member path, not one a read elsewhere left behind (agora #416).
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #416: `F → . p vs` of a block-local holder of statics, copied out, after `. q vs` of a holder viewing a block local was read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { ( Vec s ) vs }

@ main → i {
    : ~ ( Vec s ) r ( vec_new [s] )
    : ?i o @ ?i { F }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : ~ P p @ P { ( vec_new [s] ) }
        ( vec_push [s] . p vs `static` )
        : ~ P q @ P { ( vec_new [s] ) }
        ( vec_push [s] . q vs ( string_data t ) )
        = r ?? o { T m → ( vec_new [s] ) F → . p vs }
    }
    ?? ( vec_get [s] r 0 ) { T v → ( nurl_println v ) F → {} }
    ^ 0
}

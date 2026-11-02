// qq_value_arm_vec_field_after_a_same_named_read_in_another_function: agora #416 — `F → . p vs`, after `. x vs` was read in another function and main has its own `x`
// Guard: a `??` field arm is taken by its own member path, not one a read elsewhere left behind (agora #416).
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #416: `F → . p vs`, after `. x vs` was read in another function and main has its own `x`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { ( Vec s ) vs }
: P4 { ( @ v ) cb }

@ cnt P x → i { ^ ( vec_len [s] . x vs ) }

@ main → i {
    : ~ ( Vec s ) r ( vec_new [s] )
    : ?i o @ ?i { F }
    : ~ ( Vec s ) hp ( vec_new [s] )
    ( vec_push [s] hp `static` )
    : ~ P p @ P { hp }
    {
        : String t ( string_from `the first heap string, long enough to be on the heap for sure` )
        : ~ ( Vec s ) hx ( vec_new [s] )
        ( vec_push [s] hx ( string_data t ) )
        : P x @ P { hx }
        ( nurl_println_int ( cnt x ) )
        = r ?? o { T m → ( vec_new [s] ) F → . p vs }
    }
    ?? ( vec_get [s] r 0 ) { T v → ( nurl_println v ) F → {} }
    ^ 0
}

// cursor_bound_to_a_value_block_of_its_own_local_assigned_a_fresh_value_runs_clean: agora #615 guard — `: ~ ( Vec String ) w { : ~ ( Vec String ) u … u }`, then `= w ( vec_new [String] )` and `( eat w )` with `eat` taking a `sink`; the same with a struct.
// Guard: a `: ~` binding of such a block is read as before, a borrow that the assignment gives a value of its own: the block's local releases the first value and the sink takes the second. Bound as a cursor over u (the bare `: ~ w u`), the sink would take u's value away as well and nobody would release it.
// main 0b31adec: accepted; ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #615 guard: a `: ~` binding of a value block of the block's own local, assigned a fresh value and handed to a sink
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ eat sink ( Vec String ) v → i { ^ # i ( vec_len [String] v ) }

@ eatp sink P x → i { ^ + ( string_len . x name ) . x n }

@ main → i {
    : ~ ( Vec String ) w { : ~ ( Vec String ) u ( vec_new [String] ) ( vec_push [String] u ( string_from `an element string long enough for a heap buffer` ) ) u }
    = w ( vec_new [String] )
    ( vec_push [String] w ( string_from `a second element string long enough for the heap` ) )
    ( nurl_println_int ( eat w ) )
    : ~ P e { : P p @ P { ( string_from `inner string long enough for a heap buffer` ) 2 } p }
    = e @ P { ( string_from `a replacement string, also long enough for the heap` ) 3 }
    ( nurl_println_int ( eatp e ) )
    ^ 0
}

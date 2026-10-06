// sink_param_from_join.nu — a `sink` parameter handed back through a `??`
// join arm moves out; on the other arm it is dropped.
//
// `^ ?? o { T v → v F → dflt }`: the join took `dflt` for an outer binding
// that is only lent, so the function still dropped it on return and the
// caller received freed memory (core/option.nu's opt_unwrap_or shape;
// stdlib csv_dict_reader_new on empty input).

$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ mk i n → ( Vec i ) {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i k 0
    ~ < k n { ( vec_push [i] v k ) = k + k 1 }
    ^ v
}

@ pick_join sink ? ( Vec i ) o sink ( Vec i ) dflt → ( Vec i ) {
    ^ ?? o { T v → v F → dflt }
}

@ main → i {
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        : ?( Vec i ) none @ ?( Vec i ) { F # ( Vec i ) 0 }
        : ( Vec i ) a ( pick_join none ( mk 3 ) )
        : ( Vec i ) b ( pick_join @ ?( Vec i ) { T ( mk 2 ) } ( mk 5 ) )
        = acc + + acc ( vec_len [i] a ) ( vec_len [i] b )
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}

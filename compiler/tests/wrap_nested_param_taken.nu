// wrap_nested_param_taken.nu — a parameter placed in a literal nested in a
// returned option is taken over, as in a literal returned bare.
//
// `^ @ ?Box2 { T @ Box2 { shape v } }` lent `shape` back to the caller, as
// `^ @ ?T { T p }` does with a whole payload — but beside the fresh `v` the
// payload cannot be a lend: the caller took the whole result for borrowed
// and `v` leaked once per call (packages/tensor's tensor_reshape). The
// parameter now moves in; on the path that returns nothing, the function
// drops it.

$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Box2 { ( Vec i ) shape ( Vec i ) v }

@ mk ( Vec i ) shape i n → ?Box2 {
    ? < n 0 { ^ @ ?Box2 { F } } {}
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v n )
    ^ @ ?Box2 { T @ Box2 { shape v } }
}

@ round i k → i {
    : ( Vec i ) sh ( vec_new [i] )
    ( vec_push [i] sh 3 )
    ^ ?? ( mk sh k ) { T b → + ( vec_len [i] . b v ) ( vec_len [i] . b shape ) F → 0 }
}

@ main → i {
    : i l0 ( live )
    : ~ i k 0
    : ~ i s 0
    ~ < k 20 { = s + s ( round - k 5 ) = k + k 1 }
    ( nurl_print `sum ` ) ( nurl_print_int s ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}

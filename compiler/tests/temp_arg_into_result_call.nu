// temp_arg_into_result_call.nu — a temporary handed to a call that returns
// an option / result of Strings, Vecs or numbers is dropped after the call.
//
// `?? ( lsm_put db ( key_of k ) v ) { … }`: the key the inner call built was
// kept for a consumer of the result, as if the `!T E` might point into it —
// but a result of values holds no address the callee did not build, and the
// key leaked on every put (packages/lsmdb, wave-1 package sweep). The same
// for a struct of plain numbers: `( arima_update ( model_at t j ) y )` kept
// the model's share (packages/anomaly).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ report s what i d → v { ( nurl_print what ) ( nurl_print_int d ) ( nurl_print `\n` ) }

@ mk i n → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    ( vec_push [u] v # u n )
    ^ v
}

@ r_str ( Vec u ) k → !i String { ^ @ !i String { T ( vec_len [u] k ) } }

@ r_vec ( Vec u ) k → !( Vec i ) String {
    : ( Vec i ) out ( vec_new [i] )
    ( vec_push [i] out ( vec_len [u] k ) )
    ^ @ !( Vec i ) String { T out }
}

@ o_str ( Vec u ) k → ?String { ^ @ ?String { T ( string_from `x` ) } }

: Pt { f x f y }

@ p_of ( Vec u ) k → Pt { ^ @ Pt { # f ( vec_len [u] k ) 1.0 } }

@ main → i {
    : ~ i k 0
    : ~ i l0 ( live )
    = k 0 ~ < k 20 { : !i String r ( r_str ( mk k ) ) = k + k 1 }
    ( report `!i String: ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { : !( Vec i ) String r ( r_vec ( mk k ) ) = k + k 1 }
    ( report `!( Vec i ) String: ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { : ?String r ( o_str ( mk k ) ) = k + k 1 }
    ( report `?String: ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { : Pt r ( p_of ( mk k ) ) = k + k 1 }
    ( report `struct of numbers: ` - ( live ) l0 )
    = l0 ( live )
    : ~ i acc 0
    = k 0 ~ < k 20 { = acc + acc ?? ( r_str ( mk k ) ) { T n → n F _ → 0 } = k + k 1 }
    ( report `?? ( r_str ( mk k ) ): ` - ( live ) l0 )
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ^ 0
}

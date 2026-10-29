// H729: as h725, the join a `??` over an option, each arm a literal.
// Closed: the join's ownership bit is taken for the call before
// mem_lent_cond consumes it (arg_join_own), and mem_arg_temps drops the
// joined value by it unless the callee keeps, consumes or hands it back
// (agora #174).
// v0.80.0: HOLE (detected memory leaks).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String s i pad }

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

@ mkv i n → ( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v n ) ^ v }

@ use S h → i { ^ ( string_len . h s ) }

@ main → i {
    : ~ i n 0
    ~ < n 4 {
        ( nurl_println_int ( use ?? ( vec_get [i] ( mkv n ) 0 ) { T x → @ S { ( mk ) x } F _ → @ S { ( mk ) 0 } } ) )
        = n + n 1
    }
    ^ 0
}

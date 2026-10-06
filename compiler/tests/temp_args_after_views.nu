// temp_args_after_views.nu — a temporary handed to a call that cannot
// point into it is dropped right after that call.
//
// `( vec_get [i] ( mk ) 0 )`: vec_get reads an element of its argument, so
// the temporary was kept for a consumer of the result — but a `?i` holds no
// address, nothing consumed it, and the Vec leaked (packages/nwasm's JIT
// setcc table). `( copy_of ( string_data ( make ) ) )`: the String behind the
// view waited for a call returning a number; one returning a String it
// builds rather than hands back never released it (swarm-mcp's token flag).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ mk → ( Vec i ) {
    : ( Vec i ) t ( vec_new [i] )
    ( vec_push [i] t 7 )
    ^ t
}

@ report s what i d → v { ( nurl_print what ) ( nurl_print_int d ) ( nurl_print `\n` ) }

@ make → String { ^ ( string_from `abcdef` ) }

@ len_of s x → i { ^ ( nurl_str_len x ) }

@ copy_of s x → String { ^ ( string_from x ) }

@ one_len → i {
    : i n ( len_of ( string_data ( make ) ) )
    ^ n
}

@ one_copy → i {
    : String c ( copy_of ( string_data ( make ) ) )
    ^ ( string_len c )
}

@ main → i {
    : ~ i acc 0
    : ~ i k 0
    : ~ i l0 ( live )
    = k 0 ~ < k 20 { = acc + acc ?? ( vec_get [i] ( mk ) 0 ) { T x → x F → 0 } = k + k 1 }
    ( report `?? ( vec_get ( mk ) 0 ): ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { : ?i o ( vec_get [i] ( mk ) 0 ) = acc + acc ?? o { T x → x F → 0 } = k + k 1 }
    ( report `: ?i o ( vec_get ( mk ) 0 ): ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { = acc + acc ( vec_len [i] ( mk ) ) = k + k 1 }
    ( report `( vec_len ( mk ) ): ` - ( live ) l0 )
    = l0 ( live )
    = k 0 ~ < k 20 { : ( Vec i ) t ( mk ) = acc + acc ?? ( vec_get [i] t 0 ) { T x → x F → 0 } = k + k 1 }
    ( report `bound then vec_get: ` - ( live ) l0 )

    = k 0
    : ~ i sum 0
    : i b0 ( live )
    ~ < k 20 { = sum + sum ( one_len ) = k + k 1 }
    : i b1 ( live )
    ( nurl_print `len_of: ` ) ( nurl_println ? == b0 b1 `steady` `GROWING` )
    = k 0
    ~ < k 20 { = sum + sum ( one_copy ) = k + k 1 }
    : i b2 ( live )
    ( nurl_print `copy_of: ` ) ( nurl_print ? == b1 b2 `steady` `GROWING` )
    ( nurl_print ` (` ) ( nurl_print_int - b2 b1 ) ( nurl_println ` allocations left over after 20 calls)` )
    ( nurl_print `sum (want 240): ` ) ( nurl_println_int sum )
    ^ 0
}

// join_into_keeper_moves.nu — a `?` / `??` join handed to a parameter that
// keeps it moves the owned value it picked; only a borrowed arm is copied.
//
// `( vec_push [String] v ? c ( string_from `a` ) ( string_from `b` ) )`:
// the join knew both arms were owned, but an argument (or a literal field)
// built from a join was always taken for a lend — the keeper got a copy
// and the original leaked on every call. Found as a leak in the anomaly
// package's MCP time formatting (`json_obj_set out k ? > t 0 ( … ) (
// json_clone v )`).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Box { ( Vec String ) items }

@ put Box b String s → v { ( vec_push [String] . b items s ) }

@ round b c → i {
    : String kept ( string_from `borrowed arm` )
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ? c ( string_from `a` ) ( string_from `b` ) )
    ( vec_push [String] v ? c ( string_from `owned arm` ) kept )
    : Box bx @ Box { ( vec_new [String] ) }
    ( put bx ? c ( string_from `a` ) ( string_from `bb` ) )
    : Box by @ Box { ( vec_new [String] ) }
    ( vec_push [String] . by items ?? ( vec_get [String] v 0 ) { T s → ( string_from `found` ) F → ( string_from `none` ) } )
    ^ + + + ( vec_len [String] v ) ( string_len kept ) ( vec_len [String] . bx items ) ( vec_len [String] . by items )
}

@ main → i {
    : i a ( round T )
    : i b ( round F )
    : i l0 ( live )
    : ~ i k 0
    ~ < k 20 { : i x ( round T ) : i y ( round F ) = k + k 1 }
    ( nurl_println ( nurl_str_cat3 ( nurl_str_int a ) ` ` ( nurl_str_int b ) ) )
    ( nurl_println ? == l0 ( live ) `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - ( live ) l0 ) ) )
    ^ 0
}

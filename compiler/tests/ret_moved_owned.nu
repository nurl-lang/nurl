// ret_moved_owned.nu — owned values that leave a function inside the
// struct it returns, where the caller must drop them. Each shape runs for
// several rounds: the live allocation count must not grow.
//
//   - an owned raw string binding placed in a returned struct literal
//     (`^ @ Opt { model 0 }`): the binding's drop is skipped, so the field
//     is the caller's to free — it was marked owned only when the value
//     was a fresh call written in place;
//   - a parameter the function keeps (freed on one path) returned inside a
//     wrapped struct (`^ @ ?Tt { T @ Tt { 1 shape } }`): the caller hands
//     its value over, so what comes back is owned, not a borrow of it.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

: Opt { s model i bad }

@ opt_bound → Opt {
    : s model ( nurl_str_cat `model-` `path` )
    ^ @ Opt { model 0 }
}

@ opt_reassigned i which → Opt {
    : ~ s model ``
    ? > which 0 { : s v ( nurl_str_cat `model-` `path` ) = model v } {}
    ^ @ Opt { model 0 }
}

@ opt_fresh → Opt {
    ^ @ Opt { ( nurl_str_cat `model-` `path` ) 0 }
}

: Tt { i dt ( Vec i ) shape }

@ reshape ( Vec i ) shape → ?Tt {
    ? == ( vec_len [i] shape ) 0 {
        ( vec_free [i] shape )
        ^ @ ?Tt { F }
    } {}
    ^ @ ?Tt { T @ Tt { 1 shape } }
}

@ round → i {
    : ~ i acc 0
    : Opt a ( opt_bound )
    : Opt b ( opt_reassigned 1 )
    : Opt c ( opt_reassigned 0 )
    : Opt d ( opt_fresh )
    = acc + + + + acc ( nurl_str_len . a model ) ( nurl_str_len . b model ) ( nurl_str_len . c model ) ( nurl_str_len . d model )
    : ( Vec i ) s ( vec_zeroed [i] 3 )
    ?? ( reshape s ) { T r → { = acc + acc ( vec_len [i] . r shape ) } F _ → {} }
    : ( Vec i ) e ( vec_new [i] )
    ?? ( reshape e ) { T r → { = acc + acc 100 } F _ → { = acc + acc 1000 } }
    : ?Tt o ( reshape ( vec_zeroed [i] 2 ) )
    ?? o { T r → { = acc + acc ( vec_len [i] . r shape ) } F _ → {} }
    ^ acc
}

@ main → i {
    : i r1 ( round )
    : i l1 ( live )
    : i r2 ( round )
    : i r3 ( round )
    : i l3 ( live )
    ( puts ( nurl_str_int r1 ) )
    ( puts ( nurl_str_int + r2 r3 ) )
    ? == l1 l3 { ( puts `live allocations: steady` ) } { ( puts ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - l3 l1 ) ) ) }
    ^ 0
}

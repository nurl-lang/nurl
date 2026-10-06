// mem_dup_payload_into_push.nu — `( vec_push out ( mem_dup c ) )` with c
// a `vec_get` payload: the copy is fresh and moves into the Vec.
//
// The push read the last call's answer — the vec_get that produced c — as
// the copy's, took it for lent, and copied the copy; the first copy leaked
// (packages/anomaly prep.nu meta_clone_versions, every fork).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

: Cfg { String name i n }

@ clone_all ( Vec Cfg ) src → ( Vec Cfg ) {
    : ( Vec Cfg ) out ( vec_new [Cfg] )
    : ~ i k 0
    ~ < k ( vec_len [Cfg] src ) {
        ?? ( vec_get [Cfg] src k ) { T c → { ( vec_push [Cfg] out ( mem_dup c ) ) } F _ → {} }
        = k + k 1
    }
    ^ out
}

@ round → v {
    : ( Vec Cfg ) a ( vec_new [Cfg] )
    ( vec_push [Cfg] a @ Cfg { ( string_from `alpha` ) 1 } )
    ( vec_push [Cfg] a @ Cfg { ( string_from `beta` ) 2 } )
    : ( Vec Cfg ) b ( clone_all a )
}

unsafe @ main → i {
    : i a0 - ( nurl_alloc_count ) ( nurl_free_count )
    : ~ i k 0
    ~ < k 10 { ( round ) = k + k 1 }
    : i a1 - ( nurl_alloc_count ) ( nurl_free_count )
    ( nurl_print `leaked ` ) ( nurl_print_int - a1 a0 ) ( nurl_println `` )
    ^ 0
}

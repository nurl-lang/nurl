// return_lent_call_on_local.nu — `^ ( sane o )` where sane hands back a
// cursor over its borrowed parameter and o is this frame's own struct: the
// result is copied on the way out, so o is dropped and the copy is the
// caller's to own.
//
// The copy was made, but o's drop was still skipped as if the result were
// o itself, and the function published its result as lent — the caller
// copied it again (packages/anomaly prep.nu _an_vercfg_patch: a String per
// metadata version patch).

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

: Cfg { String name i n }

@ sane Cfg c → Cfg {
    : ~ Cfg o c
    ? < . o n 0 { = . o n 0 } {}
    ^ o
}

@ patch Cfg c i v → Cfg {
    : Cfg o @ Cfg { ( string_from `x` ) v }
    ^ ( sane o )
}

@ round → v {
    : ( Vec Cfg ) vs ( vec_new [Cfg] )
    ( vec_push [Cfg] vs @ Cfg { ( string_from `alpha` ) 1 } )
    ?? ( vec_get [Cfg] vs 0 ) {
        T cur → { : b _o ( vec_set [Cfg] vs 0 ( patch cur 7 ) ) }
        F _ → {}
    }
}

unsafe @ main → i {
    : i a0 - ( nurl_alloc_count ) ( nurl_free_count )
    : ~ i k 0
    ~ < k 10 { ( round ) = k + k 1 }
    : i a1 - ( nurl_alloc_count ) ( nurl_free_count )
    ( nurl_print `leaked ` ) ( nurl_print_int - a1 a0 ) ( nurl_println `` )
    ^ 0
}

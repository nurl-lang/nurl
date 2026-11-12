// enum_field_of_a_call_matched_in_place_is_dropped.nu — a user enum field
// read straight out of a call's result and matched there, `?? . ( mkapp )
// ev { Got p → … }`: the read takes the field over under the call's flag
// (gen_member), and the match gives it the owner a call's own enum gets
// (h233), with that flag. It is dropped after the match where the call
// handed its result over, and left alone where the call lent it (vec_at,
// arc_get, a function lending on some calls). Nothing took it over, and
// each such match leaked the payload's box and its Vec (Agora #764).
// Run under the sanitizer corpus with leaks checked.
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/panic.nu`

: Pair { ( Vec i ) v i n }

: | Ev { Nil Got Pair }

: App { ? Pair op Ev ev i n }

: Outer { App a i n }

@ mkpair → Pair { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 5 ) ^ @ Pair { v 1 } }

@ mkapp → App { ^ @ App { @ ?Pair { T ( mkpair ) } @ Ev { Got ( mkpair ) } 1 } }

@ mkouter → Outer { ^ @ Outer { ( mkapp ) 2 } }

@ eat sink Pair p → i { ^ ( vec_len [i] . p v ) }

@ growp Pair p i k → v { ( vec_push [i] . p v k ) }

@ late i k → i {
    ? == k 1 { ( panic `late` ) } {}
    ^ k
}

@ firstpair → Pair { ^ ?? . ( mkapp ) ev { Got p → p Nil → ( mkpair ) } }

@ pick ( Vec App ) apps b fresh → App {
    ? fresh { ^ ( mkapp ) } {}
    ^ ( vec_at [App] apps 0 )
}

@ panics → v { ?? . ( mkapp ) ev { Got p → { : i z ( late 1 ) ( nurl_println_int z ) } Nil → {} } }

@ main → i {
    ?? . ( mkapp ) ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ?? . ( mkapp ) ev { Got p → { ( growp p 3 ) ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ?? . ( mkapp ) ev { Got p → { ( nurl_println_int ( eat p ) ) } Nil → {} }
    : ~ i k 0
    : ~ i t 0
    ~ < k 100 { ?? . ( mkapp ) ev { Got p → { = t + t ( vec_len [i] . p v ) } Nil → {} } = k + k 1 }
    ( nurl_println_int t )
    : Pair q ( firstpair )
    ( nurl_println_int ( vec_len [i] . q v ) )
    ?? . . ( mkouter ) a ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ?? ( recover \ → v { ( panics ) } ) { T _ → { ( nurl_println `no panic` ) } F _ → { ( nurl_println `recovered` ) } }
    // (Lent: left with its owner.)
    : ( Vec App ) apps ( vec_new [App] )
    ( vec_push [App] apps ( mkapp ) )
    ?? . ( vec_at [App] apps 0 ) ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    : ( Arc App ) a ( arc_new [App] ( mkapp ) )
    ?? . ( arc_get [App] a ) ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ?? . ( pick apps T ) ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ?? . ( pick apps F ) ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ( nurl_println_int ( vec_len [App] apps ) )
    ^ 0
}

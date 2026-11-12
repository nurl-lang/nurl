// enum_field_of_a_lent_call_matched_in_place_is_left_with_its_owner_runs_clean: `?? . ( vec_at [App] apps 0 ) ev { … }` and `?? . ( arc_get [App] a ) ev { … }`, each twice
// Guard for agora #764's fix: where the call lent its result, the flag says so and the field is left with its owner.
// main dc7f5adf: accepted, clean.
// map: §7.6 | A2 | runs-clean | - | agora #764 guard: a user enum field of a call that lends its result is not dropped by the match
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Pair { ( Vec i ) v i n }
: | Ev { Nil Got Pair }
: App { ? Pair op Ev ev i n }

@ mkpair → Pair { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 5 ) ^ @ Pair { v 1 } }

@ mkapp → App { ^ @ App { @ ?Pair { T ( mkpair ) } @ Ev { Got ( mkpair ) } 1 } }

@ eat sink Pair p → i { ^ ( vec_len [i] . p v ) }

@ growp Pair p i k → v { ( vec_push [i] . p v k ) }

@ main → i {
    : ( Vec App ) apps ( vec_new [App] )
    ( vec_push [App] apps ( mkapp ) )
    ?? . ( vec_at [App] apps 0 ) ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    : ( Arc App ) a ( arc_new [App] ( mkapp ) )
    ?? . ( arc_get [App] a ) ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ?? . ( arc_get [App] a ) ev { Got p → { ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ^ 0
}

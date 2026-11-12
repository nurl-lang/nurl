// borrow_enum_field_of_a_call_matched_in_place.nu — a user enum field read
// straight out of a call's result and matched there, `?? . ( arc_get [App]
// mine ) ev { Got p → … }`: the read takes the field over under the call's
// flag, so where the call lends (arc_get, vec_at) the payload is a view of
// what the call lends from (Agora #681). Changing it is refused by the
// frozen-Arc rule, and growing it ends a view of the Vec's element, as for
// the option field beside it. Decided at module end from the call's
// summaries; a field of a fresh call's result stays the arm's own.
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/arc.nu`

: Pair { ( Vec i ) v i n }

: | Ev { Nil Got Pair }

: App { ? Pair op Ev ev i n }

@ mkpair → Pair { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 5 ) ^ @ Pair { v 1 } }

@ mkapp → App { ^ @ App { @ ?Pair { T ( mkpair ) } @ Ev { Got ( mkpair ) } 1 } }

@ growp Pair p i k → v { ( vec_reserve [i] . p v + 4096 k ) }

@ eat sink Pair p → i { ^ ( vec_len [i] . p v ) }

@ inarc ( Arc App ) mine → v {
    ?? . ( arc_get [App] mine ) ev { Got p → { ( growp p 1 ) } Nil → {} }
}

@ main → i {
    : ( Vec App ) apps ( vec_new [App] )
    ( vec_push [App] apps ( mkapp ) )
    ?? . ( vec_at [App] apps 0 ) ev {
        Got p → {
            : ( Slice i ) sl ( slice_from_vec [i] . p v )
            ?? . ( vec_at [App] apps 0 ) ev { Got q → { ( growp q 3 ) } Nil → {} }
            ( nurl_println_int ( slice_at [i] sl 0 ) )
        }
        Nil → {}
    }
    ( inarc ( arc_new [App] ( mkapp ) ) )
    // (A fresh call's field is the arm's own: handed to a sink, accepted.)
    ?? . ( mkapp ) ev { Got p → { ( nurl_println_int ( eat p ) ) } Nil → {} }
    ^ 0
}

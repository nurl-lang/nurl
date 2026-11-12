// enum_payload_of_a_vec_element_field_matched_in_place_grown_is_refused: a Slice of `p`'s Vec from `?? . ( vec_at [App] apps 0 ) ev { Got p → … }`, then the same field matched again and its Vec grown, then the Slice read
// Closed: agora #681, the payload borrows `apps` through vec_at, so growing it ends the Slice.
// main ffce8adb: accepted (ASan: heap-use-after-free).
// map: §2.10 | A2 | rejected | - | agora #681: a user enum payload of a vec_at field matched in place is a borrow of the Vec, ended by growing it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Pair { ( Vec i ) v i n }
: | Ev { Nil Got Pair }
: App { ? Pair op Ev ev i n }

@ mkpair → Pair { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 5 ) ^ @ Pair { v 1 } }

@ mkapp → App { ^ @ App { @ ?Pair { T ( mkpair ) } @ Ev { Got ( mkpair ) } 1 } }

@ growp Pair p i k → v { ( vec_reserve [i] . p v 4096 ) }

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
    ^ 0
}

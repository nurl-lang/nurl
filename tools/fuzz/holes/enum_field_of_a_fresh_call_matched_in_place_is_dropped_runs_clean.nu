// enum_field_of_a_fresh_call_matched_in_place_is_dropped_runs_clean: `?? . ( mkapp ) ev { Got p → … }` in a loop of 100, with the payload read, handed to a `sink`, and grown
// Closed: agora #764, a field the read took out of a call's result gets the h233 owner a call's own enum gets, under the read's flag.
// main dc7f5adf: accepted (LSan: 7 KB leaked, the payload box and its Vec each round).
// map: §7.6 | A2 | runs-clean | - | agora #764: a user enum field of a fresh call matched in place is dropped after the match
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
    : ~ i k 0
    : ~ i t 0
    ~ < k 100 { ?? . ( mkapp ) ev { Got p → { = t + t ( vec_len [i] . p v ) } Nil → {} } = k + k 1 }
    ?? . ( mkapp ) ev { Got p → { ( nurl_println_int ( eat p ) ) } Nil → {} }
    ?? . ( mkapp ) ev { Got p → { ( growp p 3 ) ( nurl_println_int ( vec_len [i] . p v ) ) } Nil → {} }
    ^ 0
}

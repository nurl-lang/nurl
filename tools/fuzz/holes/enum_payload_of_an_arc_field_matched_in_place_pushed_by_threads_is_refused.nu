// enum_payload_of_an_arc_field_matched_in_place_pushed_by_threads_is_refused: eight threads each `?? . ( arc_get [App] mine ) ev { Got p → { ( vec_push [i] . p v k ) } … }`
// Closed: agora #681, as for the helper form.
// main ffce8adb: accepted (ASan: attempting double-free, in a worker thread).
// map: §6.5 | A3 | rejected | - | agora #681: a user enum payload of an arc_get field, pushed to in the arm itself, is refused by the frozen-Arc rule
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Pair { ( Vec i ) v i n }
: | Ev { Nil Got Pair }
: App { ? Pair op Ev ev i n }

@ mkpair → Pair { ^ @ Pair { ( vec_new [i] ) 1 } }

@ mkapp → App { ^ @ App { @ ?Pair { T ( mkpair ) } @ Ev { Got ( mkpair ) } 1 } }

@ growp Pair p i k → v { ( vec_push [i] . p v k ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ?? . ( arc_get [App] mine ) ev { Got p → { ( vec_push [i] . p v k ) } Nil → {} }
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine 3000 ) }
        ?? ( thread_spawn body ) { T th → { ( vec_push [Thread] ts th ) } F e → {} }
        = t + t 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    ^ 0
}

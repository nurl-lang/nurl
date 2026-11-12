// enum_scalar_payload_of_an_arc_field_matched_in_place_runs_clean: eight threads each `?? . ( arc_get [App] mine ) ev { Num x → … Got p → {} … }`, a scalar payload
// Guard for agora #681's fix: a payload that owns nothing, of an Arc's enum field, stays accepted.
// main ffce8adb: accepted, clean.
// map: §6.5 | A3 | runs-clean | - | agora #681 guard: a scalar user enum payload matched in place on a field of arc_get stays accepted
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: Pair { ( Vec i ) v i n }
: | Ev { Nil Got Pair Num i }
: App { ? Pair op Ev ev i n }

@ mkpair → Pair { ^ @ Pair { ( vec_new [i] ) 1 } }

@ mkapp → App { ^ @ App { @ ?Pair { T ( mkpair ) } @ Ev { Got ( mkpair ) } 1 } }

@ growp Pair p i k → v { ( vec_push [i] . p v k ) }

@ reader ( Arc App ) mine i n → v {
    : ~ i k 0
    ~ < k n {
        ?? . ( arc_get [App] mine ) ev { Num x → { ( nurl_println_int + x k ) } Got p → {} Nil → {} }
        = k + k 1
    }
}

@ main → i {
    : ( Arc App ) shared ( arc_new [App] ( mkapp ) )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i t 0
    ~ < t 8 {
        : ( Arc App ) mine ( arc_clone [App] shared )
        : ( @ v ) body \ → v { ( reader mine 3 ) }
        ?? ( thread_spawn body ) { T th → { ( vec_push [Thread] ts th ) } F e → {} }
        = t + t 1
    }
    : ~ i q 0
    ~ < q ( vec_len [Thread] ts ) { : i joined ( thread_join ( vec_at [Thread] ts q ) ) = q + q 1 }
    ^ 0
}

// diag_thread_arc_reader_grows_option_field_payload.nu — an Arc's payload
// is frozen through the payload of a `??` over one of its fields as well
// (docs/MEMORY.md §6.5; agora #646). `r` is the Inner the option field
// holds, not a copy of it: the Vec bound out of it is the Arc's own, and
// the push reallocates a buffer every clone's thread reads with no lock.
// A copy of the field may be grown
// (thread_sync_copy_made_by_a_callee.nu).

$ `stdlib/std/arc.nu`
$ `stdlib/core/vec.nu`

: Inner { ( Vec i ) v i n }

: App { ? Inner oin i n }

// Counts a visit — in the Vec the payload's option holds.
@ tally App x i k → v {
    ?? . x oin {
        T r → {
            : ( Vec i ) c . r v
            ( vec_push [i] c k )
        }
        F → {}
    }
}

@ main → i {
    : ( Arc App ) held ( arc_new [App] @ App { @ ?Inner { T @ Inner { ( vec_new [i] ) 0 } } 1 } )
    ( tally ( arc_get [App] held ) 5 )
    ^ 0
}

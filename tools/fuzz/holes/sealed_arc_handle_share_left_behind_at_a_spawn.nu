// sealed_arc_handle_share_left_behind_at_a_spawn:
// AGORA-869: closed (main 3358873a: faulted under ASan); agora #689.
// map: §6.5 | B | runs-clean | - | agora #689: a sealed handle over an `( Arc Impl )` written through `arc_ptr`, `_share`d, one copy crossing to a thread and the other staying: thread_spawn's crossing check counts the handle's direct Arc field and panics
$ `stdlib/std/arc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/vec.nu`

: TallyImpl { ( Vec i ) v }
: Tally { ( Arc TallyImpl ) a }

unsafe @ Tally_share Tally h → Tally { ^ @ Tally { ( arc_clone [TallyImpl] . h a ) } }

unsafe @ Tally_drop sink Tally h → v {}

unsafe @ tally_new → Tally { ^ @ Tally { ( arc_new [TallyImpl] @ TallyImpl { ( vec_new [i] ) } ) } }

unsafe @ tally_add Tally h i x → v {
    : *TallyImpl p ( arc_ptr [TallyImpl] . h a )
    ( vec_push [i] . p v x )
}

@ tally_len Tally h → i { ^ ( vec_len [i] . ( arc_get [TallyImpl] . h a ) v ) }

@ main → i {
    : Tally t ( tally_new )
    : Tally mine ( Tally_share t )
    : ( @ v ) body \ → v {
        : ~ i k 0
        ~ < k 60000 { ( tally_add t k ) = k + k 1 }
    }
    ?? ( thread_spawn body ) {
        T th → {
            : ~ i k 0
            ~ < k 60000 { ( tally_add mine k ) = k + k 1 }
            : i joined ( thread_join th )
        }
        F _ → {}
    }
    ( nurl_println_int ( tally_len mine ) )
    ^ 0
}

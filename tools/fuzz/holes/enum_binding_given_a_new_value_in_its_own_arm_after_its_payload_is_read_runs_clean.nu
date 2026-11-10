// enum_binding_given_a_new_value_in_its_own_arm_after_its_payload_is_read_runs_clean: the arm reads its payload, then gives the enum binding a new value and never reads the payload again.
// Control for agora #364: only a read after the assignment is refused.
// map: §2.10 | A2 | runs-clean | - | agora #364: the arm reads its payload, then gives the enum binding a new value and never reads the payload again
$ `stdlib/core/string.nu`

: | Msg {
    MNone
    MSome String
}

@ run i k → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ( nurl_println ( string_data s ) )
            ? == k 1 { = o @ Msg { MSome ( string_from `a new owned message string long enough for the heap` ) } } {}
        }
        MNone → {}
    }
    ^ 0
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }

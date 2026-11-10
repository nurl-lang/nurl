// enum_binding_given_an_owned_literal_in_its_own_arm_then_its_payload_read: the same with an owned enum literal on the right (formal a1481_30).
// Closed: as the lent form (agora #364).
// main 04a42b2a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #364: the same with an owned enum literal on the right (formal a1481_30)
$ `stdlib/core/string.nu`

: | Msg {
    MNone
    MSome String
}

@ run i k → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ? == k 1 { = o @ Msg { MSome ( string_from `a new owned message string long enough for the heap` ) } } {}
            ( nurl_println ( string_data s ) )
        }
        MNone → {}
    }
    ^ 0
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}

// enum_binding_given_a_lent_value_in_its_own_arm_then_its_payload_read: a program enum's `: ~` binding is given a value an accessor lends inside its own `??` arm, and the arm's String payload is read after (formal a1481_24).
// Closed: `= o …` releases the old value, so a payload read in place out of it is ended there (agora #364).
// main 04a42b2a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #364: a program enum's `: ~` binding is given a value an accessor lends inside its own `??` arm, and the arm's String payload is read after (formal a1481_24)
$ `stdlib/core/string.nu`

: | Msg {
    MNone
    MSome String
}
: Box { Msg m i n }

@ msg_of Box b → Msg {
    ^ . b m
}

@ run i k → i {
    : Box bx @ Box { @ Msg { MSome ( string_from `the boxed message string long enough for the heap` ) } 1 }
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ? == k 1 { = o ( msg_of bx ) } {}
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

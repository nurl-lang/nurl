// enum_binding_replaced_in_its_own_arm_by_an_inout_callee_then_payload_read: `?? o { MSome s → { ( reset o ) ( read s ) } }`, reset taking o inout and giving it a new value: the old value and s with it were released, and s was read.
// Closed: a call that may replace an inout argument, or drop what it holds, ends the ?? arm payloads read in place out of that program-enum binding's old value, as `= o …` does since #1678 (__bck_epy_release in bck_cursor_follow; agora #565).
// main f4d6b13e: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #565: a ?? arm replacing its own enum binding through an inout callee
$ `stdlib/core/string.nu`

: | Msg {
    MNone
    MSome String
}

@ reset inout Msg m → v { = m @ Msg { MNone } }

@ run i k → i {
    : ~ Msg o @ Msg { MSome ( string_from `the owner message string long enough for the heap` ) }
    ?? o {
        MSome s → {
            ? == k 1 { ( reset o ) } {}
            ( nurl_println ( string_data s ) )
        }
        MNone → {}
    }
    ^ 0
}

@ main → i { ( run 0 ) ( run 1 ) ^ 0 }

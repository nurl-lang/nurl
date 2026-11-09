// enum_binding_cleared_in_its_own_arm_then_its_record_payloads_field_read: a program enum's binding holding a record with a String field is given a new value inside its own arm, and the payload's field is read after.
// Closed: as the String payload (agora #364).
// main 04a42b2a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #364: a program enum's binding holding a record with a String field is given a new value inside its own arm, and the payload's field is read after
$ `stdlib/core/string.nu`

: P { String name i n }
: | Msg { MNone MSome P }

@ run i k → i {
    : ~ Msg o @ Msg { MSome @ P { ( string_from `the owner record name long enough for the heap` ) 3 } }
    ?? o {
        MSome p → {
            ? == k 1 { = o @ Msg { MNone } } {}
            ( nurl_println ( string_data . p name ) )
        }
        MNone → {}
    }
    ^ 0
}

@ main → i { ( run 1 ) ^ 0 }

// payload_cursor_copy_grown_in_a_nested_second_match: a `: ~` copy of the second match's payload grown (AGORA-428's nested-match shape)
// Closed: a change through a `??` payload binding that may move its buffer ends the views of every other payload binding of the same value - its option's other cursors, an enum's other payloads read in place, and, through a borrow, the payload cursors of the owners it borrows from (bck_borrow_sweep, bck_cursor_follow; agora #874).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: a `: ~` copy of the second match's payload grown (AGORA-428's nested-match shape)
$ `stdlib/core/string.nu`

: H { String name }

@ main → i {
    : ~ ? H oh @ ?H { T @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    ?? oh {
        T q → {
            : s v ( string_data . q name )
            ?? oh { T r → { : ~ H c r ( string_push_str . c name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } F → {} }
            ( nurl_println v )
        }
        F → {}
    }
    ^ 0
}

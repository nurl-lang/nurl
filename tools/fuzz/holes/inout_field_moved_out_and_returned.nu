// inout_field_moved_out_and_returned: the same through an `inout` parameter — `: String old . r name`, `= . r name …`, `^ old` — handed the caller a string the assignment had already released, and the caller read it.
// Closed: as H196 — the replaced value moves to `old`, which owns it when it is returned.
// main (before this PR): AddressSanitizer, heap-use-after-free in the caller.
// map: §2.10 | A2 | runs-clean | h197 | inout struct field read, field replaced, old view returned to caller
$ `stdlib/core/string.nu`

: Rec { String name i n }

@ take_name inout Rec r → String {
    : String old . r name
    = . r name ( string_from `the replacement value, long enough for the heap` )
    ^ old
}

@ main → i {
    : ~ Rec r @ Rec { ( string_from `the original value, long enough for the heap` ) 1 }
    : String a ( take_name r )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data . r name ) )
    ^ 0
}

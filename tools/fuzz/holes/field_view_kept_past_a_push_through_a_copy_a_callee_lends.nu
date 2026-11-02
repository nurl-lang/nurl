// field_view_kept_past_a_push_through_a_copy_a_callee_lends: agora #440 — `: String c ( name_of hs )`, name_of handing back `. h name`, grown while a view of `. hs name` lives
// Closed: a part a call lends out of a struct (a field) moving its buffer ends the views of the struct and every path of it (bck_view_end_via, agora #440).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #440: `: String c ( name_of hs )`, name_of handing back `. h name`, grown while a view of `. hs name` lives
$ `stdlib/core/string.nu`

: H { String name }

@ name_of H h → String { ^ . h name }

@ main → i {
    : H hs @ H { ( string_from `the name, short` ) }
    : s v ( string_data . hs name )
    : String c ( name_of hs )
    ( string_push_str c ` and a much longer tail that makes the buffer move elsewhere on the heap` )
    ( nurl_println v )
    ^ 0
}

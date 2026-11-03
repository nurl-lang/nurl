// closure_hands_back_a_record_of_a_literal_and_an_owned_copy_runs_clean: a closure hands back a record whose view field is a literal and whose owned field is string_from of a view it captured.
// Closed: h220's check of an owner of views a closure hands back skips the arguments of a call whose result can hold no view (__sx_names_capture).
// main 4f15689: accepted; ran clean.
// map: §7.5 | A2 | runs-clean | h220 | a closure hands back a record of a literal view and an owned copy of a view it captured
$ `stdlib/core/string.nu`

: Tok { s w String unit }

@ main → i {
    : String u ( string_from `a unit name long enough to be on the heap for sure` )
    : s unit ( string_data u )
    : ( @ Tok ) f \ → Tok { ^ @ Tok { `lit` ( string_from unit ) } }
    : Tok t ( f )
    ( nurl_println ( string_data . t unit ) )
    ^ 0
}

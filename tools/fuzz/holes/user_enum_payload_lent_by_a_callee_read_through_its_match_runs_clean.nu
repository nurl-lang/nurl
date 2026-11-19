// user_enum_payload_lent_by_a_callee_read_through_its_match_runs_clean: AGORA-428 guard — a view a callee lends of a user enum's payload, kept while `?? g { GSome q → … }` only reads the payload: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-428 guard: a match that only reads
$ `stdlib/core/string.nu`

: H { String name }
: | G { GNone GSome H }

@ name_of G g → s { ?? g { GSome p → { ^ ( string_data . p name ) } GNone → { ^ `` } } }

@ main → i {
    : ~ G g @ G { GSome @ H { ( string_from `the option payload name, alive and long enough for the heap` ) } }
    : s v ( name_of g )
    ?? g { GSome q → { ( nurl_println_int ( string_len . q name ) ) } GNone → {} }
    ( nurl_println v )
    ^ 0
}

// enum_payload_of_a_matched_temporary_field_given_a_new_value: AGORA-883 — `?? ( mk ) { ES b → { = . b name ( string_from … ) … } … }`: the arm works on a copy of the temporary's payload, whose drop releases the old name and leaves the new one to no one (github#2079's review)
// AGORA-883 (this shape, closed): refused (main: accepted, LeakSanitizer)
// map: §2.10 | A2 | rejected | - | AGORA-883: a field of a matched temporary enum's payload given an owning value
$ `stdlib/core/string.nu`

: H { String name }
: | E { EN ES H EV ( Vec String ) }

@ mk → E { ^ @ E { ES @ H { ( string_from `the old name, long enough to own a heap buffer surely` ) } } }

@ main → i {
    ?? ( mk ) { ES b → { = . b name ( string_from `the new name, long enough to own a heap buffer too` ) ( nurl_println ( string_data . b name ) ) } EN → {} EV q → {} }
    ^ 0
}

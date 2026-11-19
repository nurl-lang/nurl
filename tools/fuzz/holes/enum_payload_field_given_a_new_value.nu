// enum_payload_field_given_a_new_value: AGORA-883 — `?? e { ES b → { = . b name ( string_from … ) } … }`, then the field read through another match
// AGORA-883 (closed): refused (main: accepted, prints the old name, LeakSanitizer: the new String leaked)
// map: §2.10 | A2 | rejected | - | AGORA-883: a field of a lent enum payload given an owning value
$ `stdlib/core/string.nu`

: H { String name }
: | E { EN ES H EV ( Vec String ) }

@ main → i {
    : ~ E e @ E { ES @ H { ( string_from `the old name, long enough to own a heap buffer surely` ) } }
    ?? e { ES b → { = . b name ( string_from `the new name, long enough to own a heap buffer too` ) } EN → {} EV q → {} }
    ?? e { ES a → { ( nurl_println ( string_data . a name ) ) } EN → {} EV q → {} }
    ^ 0
}

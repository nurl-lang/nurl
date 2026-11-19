// enum_payload_field_given_a_new_value_with_a_view_of_the_old_read_after: AGORA-883 — `?? e { ES b → { = . b name ( string_from … ) } … }` inside an arm that viewed `. a name`, the view read after
// AGORA-883 (closed): refused - the arm works on a copy of the payload the enum lends it (main: accepted, LeakSanitizer: the new String leaked)
// map: §2.10 | A2 | rejected | - | AGORA-883: a field of a lent enum payload given an owning value, a view of the old one read after
$ `stdlib/core/string.nu`

: H { String name }
: | E { EN ES H EV ( Vec String ) }

@ main → i {
    : ~ E e @ E { ES @ H { ( string_from `the old name, long enough to own a heap buffer surely` ) } }
    ?? e { ES a → {
            : s v ( string_data . a name )
            ?? e { ES b → { = . b name ( string_from `the new name, long enough to own a heap buffer too` ) } EN → {} EV q → {} }
            ( nurl_println v )
        } EN → {} EV q → {} }
    ^ 0
}

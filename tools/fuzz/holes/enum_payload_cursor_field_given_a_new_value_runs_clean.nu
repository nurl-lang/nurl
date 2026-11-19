// enum_payload_cursor_field_given_a_new_value_runs_clean: AGORA-883 guard — `?? e { ES b → { : ~ H cur b  = . cur name ( string_from … ) } … }`: the cursor's own copy takes the new value and releases it, accepted (github#2079's review)
// map: §2.10 | A2 | runs-clean | - | AGORA-883 guard: a cursor bound from an enum payload, a field given an owning value
$ `stdlib/core/string.nu`

: H { String name }
: | E { EN ES H EV ( Vec String ) }

@ main → i {
    : ~ E e @ E { ES @ H { ( string_from `the old name, long enough to own a heap buffer surely` ) } }
    ?? e { ES b → { : ~ H cur b = . cur name ( string_from `the new name, long enough to own a heap buffer too` ) } EN → {} EV q → {} }
    ?? e { ES a → { ( nurl_println ( string_data . a name ) ) } EN → {} EV q → {} }
    ^ 0
}

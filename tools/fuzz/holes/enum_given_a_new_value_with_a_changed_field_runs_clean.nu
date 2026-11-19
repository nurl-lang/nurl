// enum_given_a_new_value_with_a_changed_field_runs_clean: AGORA-883 guard — the way the refusal names: `= e @ E { ES @ H { … } }`, then the field read through a match: accepted
// map: §2.10 | A2 | runs-clean | - | AGORA-883 guard: the enum given a new value with the field changed
$ `stdlib/core/string.nu`

: H { String name }
: | E { EN ES H EV ( Vec String ) }

@ main → i {
    : ~ E e @ E { ES @ H { ( string_from `the old name, long enough to own a heap buffer surely` ) } }
    = e @ E { ES @ H { ( string_from `the new name, long enough to own a heap buffer too` ) } }
    ?? e { ES a → { ( nurl_println ( string_data . a name ) ) } EN → {} EV q → {} }
    ^ 0
}

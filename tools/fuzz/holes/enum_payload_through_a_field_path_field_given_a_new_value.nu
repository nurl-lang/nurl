// enum_payload_through_a_field_path_field_given_a_new_value: AGORA-883 — `?? . w e { ES b → { = . b name ( string_from … ) } … }`: the payload of an enum held in a field (github#2079's review)
// AGORA-883 (this shape, closed): refused
// map: §2.10 | A2 | rejected | - | AGORA-883: a field of the payload of an enum held in a field given an owning value
$ `stdlib/core/string.nu`

: H { String name }
: | E { EN ES H EV ( Vec String ) }
: W { E e i n }

@ main → i {
    : ~ W w @ W { @ E { ES @ H { ( string_from `the old name, long enough to own a heap buffer surely` ) } } 1 }
    ?? . w e { ES b → { = . b name ( string_from `the new name, long enough to own a heap buffer too` ) } EN → {} EV q → {} }
    ^ 0
}

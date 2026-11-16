// enum_payload_field_viewed_while_a_second_match_grows_it_through_a_name_another_arm_binds: the inner match binds 'b' in an ES arm and in an EV arm: the name is of no one variant, so the growth through the ES 'b' still ends the outer ES payload's view
// Closed: a change through a `??` payload binding ends the views of the other payload bindings of the same value; a name two arms of one match bind with different variants is of no one variant (__pvt_note; agora #874, CodeRabbit's review of github#1913).
// main 525613db: AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | AGORA-874: the inner match binds 'b' in two arms of different variants, the growth through one ends the outer payload's view
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: H { String name }
: | E { EN ES H EV H }

@ id ? String a → ?String { ^ a }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ grow String s → v { ( string_push_str s `, and a long tail appended to grow the buffer past its room and more` ) }

@ run i k → v {
    : ~ E e @ E { ES @ H { ( string_from `an enum payload value long enough for the heap` ) } }
    ?? e { ES a → {
            : s v ( string_data . a name )
            ?? e { ES b → { ( string_push_str . b name `, and a long tail appended to grow the buffer past its room and more` ) } EV b → {} EN → {} }
            ( nurl_println v )
        } EV q → {} EN → {} }
}

@ main → i {
    ( run 0 )
    ^ 0
}

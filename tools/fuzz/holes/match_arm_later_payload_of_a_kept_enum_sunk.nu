// match_arm_later_payload_of_a_kept_enum_sunk: a later `% Drop` payload of an enum a binding keeps, handed to a `sink` parameter from the arm.
// Closed with agora #641: the payload is lent to the arm (the enum keeps it), and a `% Drop` value cannot be copied, so the consume is refused. Before, the callee dropped it and the enum dropped it again.
// main 6040c17: accepted, heap-use-after-free in drop__Bomb.
// map: §7.6 | A2 | rejected | - | agora #641: a later % Drop payload of a kept enum handed to a sink parameter from the arm (the enum drops it too)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

@ mk3 → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ eat sink Bomb b → v { ( nurl_println ( nurl_str_cat `eat ` ( string_data . b tag ) ) ) }

@ main → i {
    : E e ( mk3 )
    ?? e {
        Zero n → { ( nurl_println `zero` ) }
        Three x s y → { ( eat y ) }
    }
    ( nurl_println `end` )
    ^ 0
}

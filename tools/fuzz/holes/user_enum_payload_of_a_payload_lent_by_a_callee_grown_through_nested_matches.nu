// user_enum_payload_of_a_payload_lent_by_a_callee_grown_through_nested_matches: AGORA-428 (CodeRabbit on github#2056) — `: v ( name_of o )`, o an enum whose payload is a user enum, then `?? o { OSome g → ?? g { GSome q → push . q name } }`: the inner payload's owner is g, whose own owner is o, so the growth must reach o
// AGORA-428: refused - a change through a payload sweeps every owner up the payload chain
// map: §2.10 | A2 | rejected | - | AGORA-428: a payload of a payload grown under a callee's lend of the outer enum
$ `stdlib/core/string.nu`

: H { String name }

: | G { GNone GSome H }

: | O { ONone OSome G }

@ name_of O o → s {
    ?? o {
        OSome g → { ?? g { GSome p → { ^ ( string_data . p name ) } GNone → { ^ `` } } }
        ONone → { ^ `` }
    }
}

@ main → i {
    : ~ O o @ O { OSome @ G { GSome @ H { ( string_from `the inner payload name, alive and long enough for the heap` ) } } }
    : s v ( name_of o )
    ?? o {
        OSome g → { ?? g { GSome q → { ( string_push_str . q name `a long tail that forces the buffer to move to a new allocation, surely, yes indeed, and then some more` ) } GNone → {} } }
        ONone → {}
    }
    ( nurl_println v )
    ^ 0
}

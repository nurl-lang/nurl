// diag_enum_payload_read_after_handover.nu — a `??` arm's payload read in
// place out of an enum binding ends when the binding is handed over whole
// (Agora #641): a `sink` callee, or one whose final summary says it takes
// the argument, drops the enum on its way out, the payload with it. Read
// after that call, the payload was read out of freed memory — the rule an
// option's payload already had (diag_payload_cursor_ends.nu), and an
// enum's only for `= e …`.
//
// A payload that holds no address (an integer) is no part of the enum's
// storage and stays readable; so does any payload read before the call.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) ) } }

@ bomb s tag → Bomb { ^ @ Bomb { ( string_from tag ) 0 } }

: | E { Zero i Three Bomb String Bomb }

@ mk → E { ^ @ E { Three ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

// The same enum with a `% Drop` of its own.
: | D { Dzero i Dthree Bomb String Bomb }

% Drop D { @ drop D d → v { ( nurl_println `drop D` ) } }

@ mkd → D { ^ @ D { Dthree ( bomb `3a` ) ( string_from `3s, long enough for the heap` ) ( bomb `3c` ) } }

@ eat sink E e → v { ( nurl_println `eat` ) }

@ eatd sink D d → v { ( nurl_println `eatd` ) }

@ string_payload → v {
    : E e ( mk )
    ?? e {
        Zero n → {}
        Three x s y → {
            ( eat e )
            ( nurl_println ( string_data s ) )
        }
    }
}

@ drop_payload → v {
    : E e ( mk )
    ?? e {
        Zero n → {}
        Three x s y → {
            ( eat e )
            ( nurl_println ( string_data . y tag ) )
        }
    }
}

@ own_drop_enum → v {
    : D d ( mkd )
    ?? d {
        Dzero n → {}
        Dthree x s y → {
            ( eatd d )
            ( nurl_println ( string_data s ) )
        }
    }
}

// A callee compiled after its caller, which hands the enum on to a `sink`.
@ through_a_later_callee → v {
    : E e ( mk )
    ?? e {
        Zero n → {}
        Three x s y → {
            ( later e )
            ( nurl_println ( string_data s ) )
        }
    }
}

@ later E e → v { ( eat e ) }

// Accepted: read before the call, and a payload that holds no address.
@ read_before → v {
    : E e ( mk )
    ?? e {
        Zero n → {
            ( eat e )
            ( nurl_println ( nurl_str_int n ) )
        }
        Three x s y → {
            ( nurl_println ( string_data s ) )
            ( eat e )
        }
    }
}

@ main → i {
    ( string_payload )
    ( drop_payload )
    ( own_drop_enum )
    ( through_a_later_callee )
    ( read_before )
    ^ 0
}

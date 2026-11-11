// enum_own_drop_payload_handover.nu — a payload of an enum with a `% Drop`
// of its own is a view of the enum wherever it goes (Agora #641).
//
// The enum is dropped whole (its impl, then its drop glue), so nothing is
// taken out of it. `^ s` by name and a join's value were already copied
// out of an enum the function drops (enum_own_drop_glue.nu); handed back
// through a `:` binding of it, inside a literal or an option, through a
// value block or a call that lends its argument back, the payload went
// out as it was, and the caller read what the glue had released
// (heap-use-after-free under the sanitizers, run_san_tests.sh). Each of
// those is a copy now where the function drops the enum — a local, a
// matched temporary, a `sink` parameter — and a lend where the enum is a
// parameter the caller keeps.
//
// A payload read before the enum is handed to a `sink`, and an integer
// payload read after, stay accepted (the read after is refused:
// diag_enum_payload_read_after_handover.nu).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Bomb { String tag i boom }

% Drop Bomb {
    @ drop Bomb b → v {
        ( nurl_println ( nurl_str_cat `drop ` ( string_data . b tag ) ) )
    }
}

@ bomb s tag i boom → Bomb { ^ @ Bomb { ( string_from tag ) boom } }

: | Ev { Quiet i Trio Bomb String Bomb Named String }

% Drop Ev { @ drop Ev e → v { ( nurl_println `drop Ev` ) } }

@ trio s a i boom → Ev { ^ @ Ev { Trio ( bomb ( nurl_str_cat a `.1` ) boom ) ( string_from ( nurl_str_cat a `: the middle payload, on the heap` ) ) ( bomb ( nurl_str_cat a `.3` ) 0 ) } }

: W { String s i n }

@ id [T] T v → T { ^ v }

// Through a `:` binding of the payload.
@ by_binding → String {
    : Ev e ( trio `binding` 0 )
    ?? e {
        Quiet n → { ^ ( string_from `quiet` ) }
        Trio x s y → { : String t s ^ t }
        Named s → { : String t s ^ t }
    }
}

// Inside a literal, and inside an option.
@ in_literal → W {
    : Ev e ( trio `literal` 0 )
    ?? e {
        Quiet n → { ^ @ W { ( string_from `quiet` ) 0 } }
        Trio x s y → { ^ @ W { s 3 } }
        Named s → { ^ @ W { s 1 } }
    }
}

@ in_option → ?String {
    ?? ( trio `option` 0 ) {
        Quiet n → { ^ @ ?String { F } }
        Trio x s y → { ^ @ ?String { T s } }
        Named s → { ^ @ ?String { T s } }
    }
}

// Through a value block, and through a call that lends its argument back.
@ by_block → String {
    : Ev e ( trio `block` 0 )
    ?? e {
        Quiet n → { ^ ( string_from `quiet` ) }
        Trio x s y → { ^ { s } }
        Named s → { ^ s }
    }
}

@ by_call sink Ev e → String {
    ?? e {
        Quiet n → { ^ ( string_from `quiet` ) }
        Trio x s y → { ^ ( id [String] s ) }
        Named s → { ^ s }
    }
}

// Out of a parameter the caller keeps: lent, through the binding too.
@ of_param Ev e → String {
    ?? e {
        Quiet n → { ^ ( string_from `quiet` ) }
        Trio x s y → { : String t s ^ t }
        Named s → { ^ s }
    }
}

@ handed_back → v {
    : String a ( by_binding )
    ( nurl_println ( string_data a ) )
    : W w ( in_literal )
    ( nurl_println ( string_data . w s ) )
    ?? ( in_option ) {
        T s → { ( nurl_println ( string_data s ) ) }
        F → { ( nurl_println `none` ) }
    }
    : String b ( by_block )
    ( nurl_println ( string_data b ) )
    : String c ( by_call ( trio `call` 0 ) )
    ( nurl_println ( string_data c ) )
    : Ev kept ( trio `param` 0 )
    : String d ( of_param kept )
    ( nurl_println ( string_data d ) )
}

// Read, then handed over; an integer payload read after the handover.
@ eat sink Ev e → v { ( nurl_println `eat` ) }

@ read_then_handed_over → v {
    : Ev e ( trio `handover` 0 )
    ?? e {
        Quiet n → { ( eat e ) ( nurl_println ( nurl_str_int n ) ) }
        Trio x s y → {
            ( nurl_println ( nurl_str_cat3 ( string_data s ) ` / ` ( string_data . y tag ) ) )
            ( eat e )
        }
        Named s → { ( eat e ) }
    }
    : Ev q @ Ev { Quiet 7 }
    ?? q {
        Quiet n → { ( eat q ) ( nurl_println ( nurl_str_int n ) ) }
        Trio x s y → {}
        Named s → {}
    }
}

@ main → i {
    ( handed_back )
    ( read_then_handed_over )
    ^ 0
}

// arm_local_call_lend_ok.nu — an arm whose value is a call's lend out of a
// binding the arm owns itself (`{ : W w ( mkw ) ( gets w ) }`) hands over a
// copy, and the arm's locals are dropped at its exit even when the join's
// value is consumed (agora #191): in a `?` arm, an else arm, a `??` arm,
// and a returned join. A lend of a binding of the enclosing code is not
// copied.

$ `stdlib/core/string.nu`

: W { String s i n }

% Drop W { @ drop W w → v { ( nurl_print `drop ` ) ( nurl_println_int . w n ) } }

@ gets W w → String { ^ . w s }

@ mkw i n → W { ^ @ W { ( string_from `a string lent out of an arm's local` ) n } }

@ pick b c → String {
    ^ ? c {
        : W w ( mkw 4 )
        ( gets w )
    } ( string_from `fresh` )
}

@ main → i {
    : b c T
    : String a ? c {
        : W w ( mkw 1 )
        ( gets w )
    } ( string_from `fresh` )
    ( nurl_println ( string_data a ) )
    : String b ? ! c ( string_from `fresh` ) {
        : W w ( mkw 2 )
        ( gets w )
    }
    ( nurl_println ( string_data b ) )
    : ?i o @ ?i { T 1 }
    : String m ?? o {
        T x → {
            : W w ( mkw 3 )
            ( gets w )
        }
        F → ( string_from `fresh` )
    }
    ( nurl_println ( string_data m ) )
    ( nurl_println ( string_data ( pick T ) ) )
    : W outer ( mkw 5 )
    : String q ? c ( gets outer ) ( string_from `fresh` )
    ( nurl_println ( string_data q ) )
    ^ 0
}

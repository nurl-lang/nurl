// defer_cleanup_releases_what_was_left_to_it.nu — the function's cleanup
// releases what a `;` defer kept back, and every exit runs it; it releases
// an owner only on the paths that left it to the cleanup (agora #630):
//   above    a `^` above the owner's binding — the binding never ran;
//   between  a `^` between the binding and the `;` — that exit released the
//            owner itself, before the defer kept anything back;
//   block    a `^` inside a value block, defers armed before and after;
//   arm      the owner and its defer inside an arm that was not taken;
//   many     a Vec, a struct and an enum kept by one defer, above an exit.
// Released at every exit all the same, the owner was freed uninitialised,
// or twice.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }
: | E { A String B i }

@ above i n → i {
    : String e ( string_from `e: a string long enough for a heap buffer, yes` )
    ; { ( nurl_println `above: first defer` ) }
    ? > n 1 { ^ ( string_len e ) } {}
    : String g ( string_concat e e )
    ; { ( nurl_println_int ( string_len g ) ) }
    ^ + n ( string_len e )
}

@ between i n → i {
    : String e ( string_from `e: a string long enough for a heap buffer, yes` )
    ; { ( nurl_println `between: first defer` ) }
    : String g ( string_concat e e )
    ? > n 1 { ^ ( string_len g ) } {}
    ; { ( nurl_println_int ( string_len g ) ) }
    ^ + n ( string_len e )
}

@ block i c → i {
    : ~ String s ( string_from `outer string long enough for a heap buffer` )
    ; { ( nurl_println ( string_data s ) ) }
    : String e { : String t ( string_from `inner string long enough for a heap buffer` ) ? == c 1 { ^ 1 } {} t }
    ; { ( nurl_println ( string_data e ) ) }
    ^ 0
}

@ arm i n → i {
    ? > n 1 { : String g ( string_from `g: a string long enough for a heap buffer, yes` ) ; { ( nurl_println_int ( string_len g ) ) } } {}
    ^ n
}

@ many i n → i {
    : i z + n 1
    ; { ( nurl_println `many: first defer` ) }
    ? > n 1 { ^ z } {}
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element long enough for a heap buffer` ) )
    : P p @ P { ( string_from `a name long enough for a heap buffer` ) n }
    : E e @ E { A ( string_from `a payload long enough for a heap buffer` ) }
    ; { ( nurl_println_int + ( vec_len [String] v ) ( string_len . p name ) ) ( nurl_println_int ?? e { A q → ( string_len q ) B k → k } ) }
    ^ + n z
}

@ main → i {
    ( nurl_println_int ( above 1 ) )
    ( nurl_println_int ( above 2 ) )
    ( nurl_println_int ( between 1 ) )
    ( nurl_println_int ( between 2 ) )
    ( nurl_println_int ( block 1 ) )
    ( nurl_println_int ( block 0 ) )
    ( nurl_println_int ( arm 1 ) )
    ( nurl_println_int ( arm 2 ) )
    ( nurl_println_int ( many 1 ) )
    ( nurl_println_int ( many 2 ) )
    ^ 0
}

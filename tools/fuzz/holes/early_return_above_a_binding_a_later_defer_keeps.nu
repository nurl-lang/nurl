// early_return_above_a_binding_a_later_defer_keeps: a defer, an early `^`, then `: String g …` (and a Vec, a struct, an enum) with a defer that reads it.
// Closed: fn_cleanup releases an owner a defer kept back only under its "left to the cleanup" flag, clear at entry and set where an exit or a scope's end skips the owner because a defer keeps it (mem_dkeep_mark). Every exit runs fn_cleanup; the early one came before the binding, whose storage was released uninitialised (agora #630).
// main d96ebfa: accepted; AddressSanitizer: SEGV in free (the String), a wild pointer (the Vec / struct / enum).
// map: §7.1 | A2 | runs-clean | - | agora #630: an early return above a binding that a later `;` defer keeps — the cleanup released storage the binding never filled
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }
: | E { A String B i }

@ one i n → i {
    : String e ( string_from `e: a string long enough for a heap buffer, yes` )
    ; { ( nurl_println `one: first defer` ) }
    ? > n 1 { ^ ( string_len e ) } {}
    : String g ( string_concat e e )
    ; { ( nurl_println_int ( string_len g ) ) }
    ^ + n ( string_len e )
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
    ( nurl_println_int ( one 1 ) )
    ( nurl_println_int ( one 2 ) )
    ( nurl_println_int ( many 1 ) )
    ( nurl_println_int ( many 2 ) )
    ^ 0
}

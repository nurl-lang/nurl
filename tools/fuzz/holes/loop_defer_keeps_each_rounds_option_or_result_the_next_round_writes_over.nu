// loop_defer_keeps_each_rounds_option_or_result_the_next_round_writes_over: `~ c { : ?String o …  : !String String r …  ; { … o … r … } }`, several rounds.
// Closed: a kept loop binding's earlier value is parked under the type the binding was REGISTERED with — an option or a result is registered under its named twin (`%__opt.String`), not as the slot's `{ i1, %String }`, and __dkr_expand asked for the slot type's drop, found none and wrote nothing (agora #671).
// main c8c3f4d: accepted; every round's option and result but the last are never released (LeakSanitizer), though a String or a Vec beside them is.
// map: §7.1 | A2 | runs-clean | - | agora #671: each round's option or result a loop body's `;` keeps, but the last, leaked
$ `stdlib/core/string.nu`

@ f i n → i {
    : ~ i k 0
    ~ < k n {
        : ?String o @ ?String { T ( string_from `o: a loop string long enough for a heap buffer` ) }
        : !String String r @ !String String { F ( string_from `r: an error long enough for a heap buffer` ) }
        ; {
            ?? o { T t → ( nurl_println_int ( string_len t ) ) F → ( nurl_println `none` ) }
            ?? r { T t → ( nurl_println_int ( string_len t ) ) F e → ( nurl_println_int ( string_len e ) ) }
        }
        = k + k 1
    }
    ^ k
}

@ main → i {
    ( nurl_println_int ( f 3 ) )
    ^ 0
}

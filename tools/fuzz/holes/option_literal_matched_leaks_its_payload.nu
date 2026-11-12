// option_literal_matched_leaks_its_payload: a `??` over an option literal that holds a fresh String (`@ ?String { T ( string_clone s ) }`), or a binding moved into it: the literal took the payload over, and the match was its last owner — released by nobody (agora #654).
// Closed: an option or result literal as the scrutinee owns its payload as a call's fresh result does (gen_match, scrut_own); the arm's payload binding takes it over, and an arm that binds it not drops it with the statement.
// main (before this PR): LeakSanitizer reported each matched literal's String (control block and buffer).
// map: §7.6 | A2 | runs-clean | - | an option literal matched by `??`, its payload a fresh String or a moved binding — leak
$ `stdlib/core/string.nu`

@ keep sink String d → i { ^ ( string_len d ) }

@ give String s → String {
    ^ ?? @ ?String { T ( string_clone s ) } { T q → q F → ( string_from `none` ) }
}

@ main → i {
    : String s ( string_from `s: a string long enough for a heap buffer, yes` )
    ?? @ ?String { T ( string_clone s ) } { T q → { : String w ( string_concat q s ) ( nurl_println_int ( string_len w ) ) } F → {} }
    ?? @ ?String { T ( string_clone s ) } { T q → { ( nurl_println_int ( keep q ) ) } F → {} }
    : i n ?? @ ?String { T ( string_clone s ) } { T q → ( string_len q ) F → 0 }
    ?? @ ?String { T ( string_clone s ) } { T _ → { ( nurl_println_int n ) } F → {} }
    : String g ( give s )
    : ~ i k 0
    ~ < k 2 {
        ?? @ ?String { T ( string_clone g ) } { T q → { ( nurl_println_int ( string_len q ) ) } F → {} }
        = k + k 1
    }
    : String m ( string_from `m: moved into the literal, also long enough` )
    ?? @ ?String { T m } { T q → { ( nurl_println_int ( string_len q ) ) } F → {} }
    ^ 0
}

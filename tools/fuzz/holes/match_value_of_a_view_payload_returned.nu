// match_value_of_a_view_payload_returned: `^ ?? t { Word w → w … }` with t holding ( string_data line ) of a local String: the function hands back a view of its own local.
// Closed: the value of a `??` whose arm hands out a view payload views what the payload views, as the statement-arm form already did (agora #367). Refused on main 9e8d4a88: this returns a view of 'line'.
// main 20892ccd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #367: a ?? used as a value returns a view payload of a local's String
$ `stdlib/core/string.nu`

: | Tok { Word s Num i Bad i }

@ first_word → s {
    : String line ( string_from `the inner string, freed when first_word returns` )
    : Tok t @ Tok { Word ( string_data line ) }
    ^ ?? t { Word w → w Num n → `` Bad m → `` }
}

@ main → i {
    ( nurl_println ( first_word ) )
    ^ 0
}

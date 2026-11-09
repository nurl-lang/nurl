// match_value_of_a_view_payload_pushed_past_its_line: `: s got ?? t { Word w → w Num n → `` }` with t holding ( string_data line ), got pushed into an outer Vec and read after line's block ends.
// Closed: the value of a `??` whose arm hands out a view payload views what the payload views, as the statement-arm form already did (agora #367). Refused on main 9e8d4a88: 'outer' holds a view of 'line'.
// main 20892ccd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #367: a ?? used as a value hands out a view payload, pushed into an outer Vec past its line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i }

@ main → i {
    : ~ ( Vec s ) outer ( vec_new [s] )
    {
        : String line ( string_from `the inner string, freed at the end of its block` )
        : Tok t @ Tok { Word ( string_data line ) }
        : s got ?? t { Word w → w Num n → `` }
        ( vec_push [s] outer got )
    }
    ( nurl_println ( vec_at [s] outer 0 ) )
    ( vec_free [s] outer )
    ^ 0
}

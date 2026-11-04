// nested_token_payload_of_an_element_dup_kept_past_its_line: mem_dup of a token payload matched out of vec_at, kept past the line it views.
// Closed: a match payload a call lends — an element read out of a Vec, a map's value — is tied to that call's lent arguments by its borrow, and holds besides what a copy of the scrutinee holds.
// main 836c0e9: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | Family G review: mem_dup of a token payload matched out of vec_at, kept past the line it views
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }
: | Slot { Full Tok Vacant i }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ~ Tok keep @ Tok { Num 0 }
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ( Vec Slot ) slots ( vec_new [Slot] )
        ( vec_push [Slot] slots @ Slot { Full @ Tok { Word ( string_data line ) } } )
        ?? ( vec_at [Slot] slots 0 ) { Full t → { = keep ( mem_dup t ) } Vacant n → {} }
    }
    ( show keep )
    ^ 0
}

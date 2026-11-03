// enum_payload_of_an_element_cloned_past_the_vec_runs_clean: vec_clone of a ( Vec s ) payload matched straight out of vec_at, kept past the Vec of items; the text lives.
// Kept: a match payload a call lends — an element read out of a Vec, a map's value — is tied to that call's lent arguments by its borrow, and holds besides what a copy of the scrutinee holds.
// main 836c0e9: accepted; ran clean.
// map: §2.13 | A2 | runs-clean | - | Family G review: vec_clone of a ( Vec s ) payload matched straight out of vec_at, kept past the Vec of items; the text lives
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Item { Words ( Vec s ) Count i }

@ main → i {
    : String text ( string_from `hello world, long enough for a heap buffer` )
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : ( Vec Item ) items ( vec_new [Item] )
        : ( Vec s ) ws ( vec_new [s] )
        ( vec_push [s] ws ( string_data text ) )
        ( vec_push [Item] items @ Item { Words ws } )
        ?? ( vec_at [Item] items 0 ) { Words w → { = keep ( vec_clone [s] w ) } Count n → {} }
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}

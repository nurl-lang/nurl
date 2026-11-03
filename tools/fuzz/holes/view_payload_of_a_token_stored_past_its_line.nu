// view_payload_of_a_token_stored_past_its_line: a view payload of a token over a block-local String stored into an outer field.
// A guard: since an enum over a line is an owner of views (agora #338), its view payload is lent from what the enum views, not from nothing.
// main 24e95a81: rejected (a guard).
// map: §2.13 | A2 | rejected | - | agora #338: a view payload of a token over a block-local String stored into an outer field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

: V { s v }

@ main → i {
    : V h @ V { `none` }
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : Tok t @ Tok { Word ( string_data line ) }
        ?? t { Word w → { = . h v w } Num n → {} Bad b → {} }
    }
    ( nurl_println . h v )
    ^ 0
}

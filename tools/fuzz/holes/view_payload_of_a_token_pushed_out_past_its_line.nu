// view_payload_of_a_token_pushed_out_past_its_line: a view payload of a token over a block-local String pushed into a Vec that outlives it.
// A guard: since an enum over a line is an owner of views (agora #338), its view payload is lent from what the enum views, not from nothing.
// main 24e95a81: rejected (a guard: making the token an owner of views must keep its payload lent).
// map: §2.13 | A2 | rejected | - | agora #338: a view payload of a token over a block-local String pushed into a Vec that outlives it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ( Vec s ) outs ( vec_new [s] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : Tok t @ Tok { Word ( string_data line ) }
        ?? t { Word w → { ( vec_push [s] outs w ) } Num n → {} Bad b → {} }
    }
    ( nurl_println ( vec_at [s] outs 0 ) )
    ^ 0
}

// struct_holding_an_enum_viewing_a_line_pushed_out: a struct with an enum field viewing a block-local String, pushed out.
// Closed: an enum holds a view when a variant's payload can (`__ty_holds_view` over the sum, `__variants_hold_view`; A2's `Ty.holdsView` of `.sum`), so a token over a line is an owner that depends on the line, as a struct with a view field is (agora #338).
// main 24e95a81: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #338: a struct with an enum field viewing a block-local String, pushed out
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

: H { Tok t String own }

@ main → i {
    : ( Vec H ) hs ( vec_new [H] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        ( vec_push [H] hs @ H { @ Tok { Word ( string_data line ) } ( string_from `own` ) } )
    }
    ( show . ( vec_at [H] hs 0 ) t )
    ^ 0
}

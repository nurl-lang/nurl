// option_of_an_enum_viewing_a_line_pushed_out: an option of an enum viewing a block-local String pushed into an outer Vec.
// Closed: an enum holds a view when a variant's payload can (`__ty_holds_view` over the sum, `__variants_hold_view`; A2's `Ty.holdsView` of `.sum`), so a token over a line is an owner that depends on the line, as a struct with a view field is (agora #338).
// main 24e95a81: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #338: an option of an enum viewing a block-local String pushed into an outer Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ( Vec ? Tok ) os ( vec_new [? Tok] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        ( vec_push [? Tok] os @ ?Tok { T @ Tok { Word ( string_data line ) } } )
    }
    ?? ( vec_at [? Tok] os 0 ) { T t → ( show t ) F → {} }
    ^ 0
}

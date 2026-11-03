// recursive_enum_viewing_a_line_pushed_out: a recursive enum (a Vec of itself) whose leaf views a block-local String, pushed out.
// Closed: an enum holds a view when a variant's payload can (`__ty_holds_view` over the sum, `__variants_hold_view`; A2's `Ty.holdsView` of `.sum`), so a token over a line is an owner that depends on the line, as a struct with a view field is (agora #338).
// main 24e95a81: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.13 | A2 | rejected | - | agora #338: a recursive enum (a Vec of itself) whose leaf views a block-local String, pushed out
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

: | Json { JStr s JArr ( Vec Json ) JNum i JOwn String }

@ main → i {
    : ( Vec Json ) top ( vec_new [Json] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ( Vec Json ) inner ( vec_new [Json] )
        ( vec_push [Json] inner @ Json { JStr ( string_data line ) } )
        ( vec_push [Json] top @ Json { JArr inner } )
    }
    ?? ( vec_at [Json] top 0 ) { JArr xs → { ?? ( vec_at [Json] xs 0 ) { JStr w → ( nurl_println w ) JArr ys → {} JNum n → {} JOwn o → {} } } JStr w → {} JNum n → {} JOwn o → {} }
    ^ 0
}

// enum_viewing_a_line_across_its_growth: a token over a String kept across a string_push_str that moves the String's buffer, then read.
// Closed: an enum holds a view when a variant's payload can (`__ty_holds_view` over the sum, `__variants_hold_view`; A2's `Ty.holdsView` of `.sum`), so a token over a line is an owner that depends on the line, as a struct with a view field is (agora #338).
// main 24e95a81: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #338: a token viewing a String kept across a push that moves the String's buffer, then read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ show Tok t → v { ?? t { Word w → ( nurl_println w ) Num n → ( nurl_println_int n ) Bad b → ( nurl_println ( string_data b ) ) } }

@ main → i {
    : ~ String line ( string_from `hello world, long enough for a heap buffer` )
    : Tok t @ Tok { Word ( string_data line ) }
    ( string_push_str line ` and more text to force a realloc of the buffer, long enough` )
    ( show t )
    ^ 0
}

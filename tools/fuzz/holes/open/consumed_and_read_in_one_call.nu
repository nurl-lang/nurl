// OPEN in 0.72.0 — one call reads a view of a String in one argument and consumes the String in a later one.
// ( f ( string_data str ) ( eat str ) ): the arguments run in order, so `eat` (a `sink String`) takes
// `str` over and releases it before `f` runs, and `f` reads its first argument — a view into the
// released buffer. Each argument is legal alone; nothing checks the view against the later move.
// ASan: heap-use-after-free in strlen (f's read), on the buffer nurl_vec_drop released at the end of eat.
$ `stdlib/core/string.nu`

@ eat sink String t → i { ^ ( string_len t ) }

@ f sink s x i n → i { ^ + n ( strlen x ) }

@ main → i {
    : String str ( string_from `hello` )
    ( nurl_println_int ( f ( string_data str ) ( eat str ) ) )
    ( nurl_println `P35-MARK` )
    ^ 0
}

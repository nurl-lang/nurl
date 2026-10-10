// H144: a view of a String in one argument and the String consumed by a later argument of the same call: the callee read the view after the move released its buffer (use after free).
$ `stdlib/core/string.nu`

@ eat sink String t → i { ^ ( string_len t ) }

@ f sink s x i n → i { ^ + n ( strlen x ) }

@ main → i {
    : String str ( string_from `hello` )
    ( nurl_println_int ( f ( string_data str ) ( eat str ) ) )
    ( nurl_println `P35-MARK` )
    ^ 0
}

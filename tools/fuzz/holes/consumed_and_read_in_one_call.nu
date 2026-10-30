// consumed_and_read_in_one_call: a view of a String in one argument and the String consumed by a later argument of the same call: the callee read the view after the move released its buffer (use after free).
// map: CallT.sink | A1 | rejected | h144 | view of String in one arg, String consumed by later arg of same call
$ `stdlib/core/string.nu`

@ eat sink String t → i { ^ ( string_len t ) }

@ f sink s x i n → i { ^ + n ( strlen x ) }

@ main → i {
    : String str ( string_from `hello` )
    ( nurl_println_int ( f ( string_data str ) ( eat str ) ) )
    ( nurl_println `P35-MARK` )
    ^ 0
}

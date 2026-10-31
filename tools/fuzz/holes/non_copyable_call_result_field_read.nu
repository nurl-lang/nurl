// non_copyable_call_result_field_read: a field that cannot be copied, read out of a call's result (`: Conn a . ( mk ) c`, or a number through it, `. . ( mk ) c fd`), was lent by a temporary nothing owned: the field's destructor never ran and the temporary's other fields leaked.
// Closed: the temporary gets an owner of its own for the rest of the scope, which drops it, and the field is lent out of it; handing the field back out of the function is rejected, as for a local's (__nc_ret_check).
// v0.78.0: accepted; LSan reported the temporary's Strings leaked, and "drop" never printed.
// map: §7.6 | A2 | runs-clean | h330 | a field that cannot be copied, read out of a call's result, was lent by a temporary nothing owned; the temporary now gets an owner for the rest of the scope and lends the field
$ `stdlib/core/string.nu`

: Conn {
    i fd
    String name
}

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

: Plain {
    Conn c
    String tag
}

@ mk → Plain {
    ^ @ Plain { @ Conn { 4 ( string_from `n` ) } ( string_from `p` ) }
}

@ main → i {
    : Conn a . ( mk ) c
    ( nurl_println ( nurl_str_int + . a fd . . ( mk ) c fd ) )
    ^ 0
}

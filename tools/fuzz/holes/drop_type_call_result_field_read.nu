// drop_type_call_result_field_read: a field read out of a call's result whose struct has a `% Drop` of its own (`: String s . ( mk ) name`) left the temporary with no owner: its destructor never ran and everything it held leaked (h266 takes a field out only where no destructor would see it gone).
// Closed: the temporary gets an owner of its own for the rest of the scope, which drops it — its destructor runs once — and the field is read out of it, lent as a local's is (a copy where it is kept).
// v0.78.0: accepted; LSan reported the temporary's Strings leaked, and "drop" never printed.
// map: §7.6 | A2 | runs-clean | h329 | a field read out of a call's result whose struct has its own %Drop left the temporary unowned: its destructor never ran and its contents leaked; the temporary now gets an owner for the rest of the scope
$ `stdlib/core/string.nu`

: Wrap {
    String name
    String tag
}

% Drop Wrap { @ drop sink Wrap w → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . w name ) ) ) } }

@ mk → Wrap {
    ^ @ Wrap { ( string_from `n` ) ( string_from `t` ) }
}

@ main → i {
    : String s . ( mk ) name
    ( nurl_println ( string_data s ) )
    ^ 0
}

// A field read out of a call's result that the read cannot take apart —
// the struct has a `% Drop` of its own, or the field cannot be copied —
// is lent by the result, which gets an owner of its own for the rest of
// the scope (h329, h330): its destructors run there, once. Before, the
// temporary had no owner at all: it leaked, and they never ran.
$ `stdlib/core/string.nu`

: Conn {
    i fd
    String name
}

% Drop Conn {
    @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop conn ` ( string_data . c name ) ) ) }
}

// No `% Drop` of its own: a field that cannot be copied.
: Plain {
    Conn c
    String tag
}

@ mkp s n → Plain {
    ^ @ Plain { @ Conn { 4 ( string_from n ) } ( string_from `p` ) }
}

// A `% Drop` of its own: a String field is copied out, the rest stays.
: Wrap {
    String name
    i n
}

% Drop Wrap {
    @ drop sink Wrap w → v { ( nurl_println ( nurl_str_cat `drop wrap ` ( string_data . w name ) ) ) }
}

@ mkw s n → Wrap {
    ^ @ Wrap { ( string_from n ) 1 }
}

@ use Conn c → i { ^ . c fd }

@ ret_copy → String { ^ . ( mkw `ret` ) name }

: Box { String s }

@ main → i {
    // a binding lent by the result
    : Conn a . ( mkp `bound` ) c
    ( nurl_println ( nurl_str_int . a fd ) )
    // a number read through a field that cannot be copied
    ( nurl_println ( nurl_str_int . . ( mkp `chain` ) c fd ) )
    // a borrowing argument
    ( nurl_println ( nurl_str_int ( use . ( mkp `arg` ) c ) ) )
    // a String out of a result with a destructor: a copy, the rest dropped
    : String s . ( mkw `copy` ) name
    ( nurl_println ( string_data s ) )
    : String r ( ret_copy )
    ( nurl_println ( string_data r ) )
    : Box b @ Box { . ( mkw `stored` ) name }
    ( nurl_println ( string_data . b s ) )
    // read on one arm only: nothing to drop on the other
    : i pick ? == ( string_len s ) 0 . . ( mkp `never` ) c fd 7
    ( nurl_println ( nurl_str_int pick ) )
    // read again on every round of a loop's condition
    : ~ i k 0
    ~ < k . . ( mkp `loop` ) c fd { = k + k 2 }
    ( nurl_println ( nurl_str_int k ) )
    ( nurl_println `end` )
    ^ 0
}

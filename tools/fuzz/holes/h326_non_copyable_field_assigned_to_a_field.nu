// H326: a field that cannot be copied, read out of a local struct and assigned to a field of another (`= . b c . p c`), went over while the struct kept it: both structs released it (and the value `b` held was released too).
// Closed: the field read is lent (mem_lent_cond), so the assignment is rejected.
// v0.78.0: accepted; ASan reported heap-use-after-free in Conn's drop.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

: Plain {
    Conn c
    i n
}

: Box {
    Conn c
    i n
}

@ main → i {
    : Plain p @ Plain { @ Conn { ( string_from `x` ) } 1 }
    : ~ Box b @ Box { @ Conn { ( string_from `y` ) } 2 }
    = . b c . p c
    ( nurl_println ( string_data . . b c name ) )
    ^ 0
}

// returned_literal_lends_a_local_field: a returned struct literal that held a field that cannot be copied, read out of a local struct (`^ @ Box { . p c 1 }`), released it with the local on the way out (and, once h324's rule made the read a lend, handed back a literal lending what the return released).
// Closed: such a field, lent out of a returned literal, has to be lent by something that outlives the return — a parameter — as `^ . p c` already had to (__nc_ret_check, h221); out of a local it is rejected.
// v0.78.0: accepted; ASan reported heap-use-after-free reading the result's field.
// map: §7.6 | A2 | rejected | h327 | a returned literal held such a field of a local struct, released with the local on the way out; it must be lent by a parameter, as ^ . p f must
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

@ mk → Box {
    : Plain p @ Plain { @ Conn { ( string_from `x` ) } 1 }
    ^ @ Box { . p c 1 }
}

@ main → i {
    : Box b ( mk )
    ( nurl_println ( string_data . . b c name ) )
    ^ 0
}

// non_copyable_field_stored_into_a_literal: a field that cannot be copied (a `% Drop` value with no clone), read out of a local struct and stored into a struct literal (`@ Box { . p c 1 }`), went over while the struct kept it: the literal and the struct each released it.
// Closed: a value that cannot be copied, read out of a field, is lent — the struct it is a field of still drops it, and a `% Drop` value has no empty state to leave behind (mem_lent_cond) — so the store is rejected; h229 rejected the same move into a `sink` argument.
// v0.78.0: accepted; ASan reported heap-use-after-free in Conn's drop.
// map: §7.6 | A2 | rejected | h324 | a %Drop field with no clone, read out of a local struct, was stored into a struct literal without being emptied; the literal and the struct each released it; such a field read is now lent and the store rejected
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
    : Box b @ Box { . p c 1 }
    ( nurl_println ( string_data . . b c name ) )
    ^ 0
}

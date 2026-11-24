// result_wrapping_an_owners_lend_read_after_the_owner_is_given_a_new_value: `: !i String k ( wrap s )  = s ( … )`, then k's error payload read
// Closed: as option_wrapping_an_owners_lend_read_after_the_owner_is_given_a_new_value, for a result whose `F` payload is the lent place: the result is not of the place's type, so it is not handed the old value (agora #1000).
// main 76bffb4ff: nurlc refuses it; --no-borrowck: AddressSanitizer: heap-use-after-free (the payload read).
// map: §7.6 | A2 | rejected | - | AGORA-1000: a result wrapping an owner's lend is read after the owner is given a new value
$ `stdlib/core/string.nu`

@ wrap String p → !i String { ^ @ !i String { F p } }

@ main → i {
    : ~ String s ( string_from `a string long enough for the heap buffer here` )
    : !i String k ( wrap s )
    = s ( string_from `another string long enough for the heap buffer` )
    ?? k { T n → { ( nurl_println_int n ) } F e → { ( nurl_println ( string_data e ) ) } }
    ( nurl_println ( string_data s ) )
    ^ 0
}

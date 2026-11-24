// option_wrapping_an_owners_lend_read_after_the_owner_is_given_a_new_value: `: ? String k ( wrap s )  = s ( … )`, then k's payload read
// Closed: the old value of a place given a new value goes to a binding that reads the place only where the binding is of the place's own type (or of its option's payload); an option a call wrapped the place's value in is not handed it, so its loan ends with the old value (agora #1000). nurlc's walk refused it already; the reference checker and the engine handed `s`'s old String to `k`, of type `? String`, and accepted it.
// main 76bffb4ff: nurlc refuses it; --no-borrowck: AddressSanitizer: heap-use-after-free (the payload read).
// map: §7.6 | A2 | rejected | - | AGORA-1000: an option wrapping an owner's lend is read after the owner is given a new value
$ `stdlib/core/string.nu`

@ wrap String p → ?String { ^ @ ?String { T p } }

@ main → i {
    : ~ String s ( string_from `a string long enough for the heap buffer here` )
    : ?String k ( wrap s )
    = s ( string_from `another string long enough for the heap buffer` )
    ?? k { T v → { ( nurl_println ( string_data v ) ) } F → { ( nurl_println `none` ) } }
    ( nurl_println ( string_data s ) )
    ^ 0
}

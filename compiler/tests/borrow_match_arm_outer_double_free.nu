// borrow_match_arm_outer_double_free.nu — what a `??` arm does to an OUTER
// binding reaches the code after the match. Both arms free `s` here, so
// the free after the match is a definite double free (ASan: heap-use-
// after-free). The arms used to be walked from an empty state with their
// exit discarded, so this compiled clean.
//
// Control: an arm's payload name shadows an outer binding of the same
// name only inside the arm — `v` freed in the arm leaves the outer `v`
// alone, and freeing that one after the match is fine.

$ `stdlib/core/string.nu`

@ positive ? i x → i {
    : String s ( string_from `abc` )
    ?? x { T n → ( string_free s ) F → ( string_free s ) }
    ( string_free s )
    ^ 0
}

@ shadow_control ? String o → i {
    : String v ( string_from `outer` )
    ?? o { T v → ( nurl_print ( string_data v ) ) F → {} }
    ^ ( string_len v )
}

@ main → i {
    ^ + ( positive @ ?i { T 1 } ) ( shadow_control @ ?String { F } )
}

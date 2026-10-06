// diag_unsafe_raw.nu — raw memory outside an `unsafe` function (spec
// §3.3d, docs/MEMORY.md §6.2). Each function below does one raw
// operation without the marking; each is rejected with the rule and the
// safe alternative. The last one does all of them inside `unsafe @` and
// is accepted.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

& `c` @ strlen s s → i

: Pair { i a i b }

@ calls_raw_primitive → i {
    : *u8 p ( nurl_alloc 16 )
    ^ 0
}

@ calls_foreign → i {
    ^ ( strlen `abc` )
}

@ casts_to_pointer String s → i {
    : *u8 p # *u8 ( string_data s )
    ^ 0
}

@ reads_through_pointer * Pair p → i {
    ^ . p a
}

@ writes_through_pointer * Pair p → v {
    = . p b 2
}

unsafe @ vouched String s → i {
    : *u8 p # *u8 ( string_data s )
    ^ + # i . p 0 ( strlen ( string_data s ) )
}

@ main → i {
    : String s ( string_from `abc` )
    ^ ( vouched s )
}

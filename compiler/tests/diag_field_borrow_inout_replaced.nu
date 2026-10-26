// A borrow of a field, and a callee handed the struct `inout` that may
// give that very field a new value: the borrow ends at the call, and
// reading it after is rejected. (A callee replacing another field leaves
// it standing: field_borrow_inout_replace.)
$ `stdlib/core/string.nu`

: Prog {
    String name
    i n
}

@ rename inout Prog p → v {
    = . p name ( string_from `new` )
}

@ main → i {
    : ~ Prog p @ Prog { ( string_from `old` ) 1 }
    : String nm . p name
    ( rename p )
    ^ ( string_len nm )
}

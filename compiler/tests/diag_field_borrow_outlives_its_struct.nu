// A binding read out of a field borrows that field of its struct: the
// struct handed to a `sink`, or given a new value, ends the borrow, and
// reading the binding after is rejected (h331, h332). Before, such a
// borrow borrowed nothing in the checker, and the read was a
// use-after-free.
$ `stdlib/core/string.nu`

: Holder {
    String name
    i n
}

@ eat sink Holder h → v {}

@ moved_away → i {
    : Holder h @ Holder { ( string_from `x` ) 1 }
    : String n . h name
    ( eat h )
    ^ ( string_len n )
}

@ replaced → i {
    : ~ Holder h @ Holder { ( string_from `x` ) 1 }
    : String n . h name
    = h @ Holder { ( string_from `y` ) 2 }
    ^ ( string_len n )
}

@ main → i {
    ^ + ( moved_away ) ( replaced )
}

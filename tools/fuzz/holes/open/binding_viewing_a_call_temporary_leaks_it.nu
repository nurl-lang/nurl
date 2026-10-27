// OPEN in v0.79.1 — a binding whose value views a call's temporary argument leaks the temporary: `: s v ( first ( string_from … ) )`, with `first` handing back `( string_data s )`. The temporary must outlive the binding, so the compiler never drops it (it is forgotten at the next statement, "a view temporary never outlives its statement") — leak, not use-after-free, because the borrow checker cannot name the temporary to keep the view from escaping it. LSan (use_stacks=0): the String and its buffer leak (agora #138).
$ `stdlib/core/string.nu`

@ first String s → s { ^ ( string_data s ) }

@ main → i {
    : s v ( first ( string_from `a string long enough to own a heap buffer here` ) )
    ( nurl_println v )
    ^ 0
}

// diag_owned_string_view.nu — a string binding that owns its buffer (one
// born from an owning call or a literal) is an owner, and a copy of it
// (`: s y x`) is a view of that buffer: it ends when the binding is given a
// new value (which frees the old buffer) or is dropped. Handed back by name
// the binding goes to the caller; a copy of it handed back, or a result
// that may be the binding itself, points into a buffer the function frees
// on the way out. (tools/fuzz/holes h113–h118.) The controls compile: the
// copy read before the binding changes, the binding itself handed back.

$ `stdlib/core/string.nu`

@ replaced → i {
    : ~ s x ( nurl_str_cat `ab` `cd` )
    : s y x
    = x ( nurl_str_cat `ef` `gh!` )
    ^ ( nurl_str_len y )
}

@ copy_handed_back s a → s {
    : s x ( nurl_str_cat a `-tail` )
    : s y x
    ^ y
}

@ clone_or_lend s v i flag → s {
    ? == flag 1 { ^ ( nurl_str_cat v `` ) } {}
    ^ v
}

@ maybe_itself_handed_back s a i flag → s {
    : s v ( nurl_str_cat a `x` )
    : s r ( clone_or_lend v flag )
    ^ r
}

@ read_before → i {
    : ~ s x ( nurl_str_cat `ab` `cd` )
    : s y x
    : i n ( nurl_str_len y )
    = x ( nurl_str_cat `ef` `gh!` )
    ^ + n ( nurl_str_len x )
}

@ itself_handed_back s a → s {
    : s x ( nurl_str_cat a `-tail` )
    ^ x
}

@ main → i {
    : s c ( copy_handed_back `h` )
    : s m ( maybe_itself_handed_back `h` 0 )
    : s t ( itself_handed_back `h` )
    ^ + + + + ( replaced ) ( nurl_str_len c ) ( nurl_str_len m ) ( read_before ) ( nurl_str_len t )
}

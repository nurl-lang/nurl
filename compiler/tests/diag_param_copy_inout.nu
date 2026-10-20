// diag_param_copy_inout.nu — a mutable copy of a parameter may not be
// passed 'inout' when its type owns anything.
//
// `: ~ Outer c b` shares b's fields (it owns none of them); a callee
// handed it 'inout' owns what it gets and would release b's field when it
// replaced it (h295). The way out is a copy of its own, ': ~ Outer c (
// mem_dup b )', which the second function shows.

$ `stdlib/core/vec.nu`

: Inner {
    i a
    ( Vec i ) items
}

: Outer {
    i n
    Inner inner
}

@ reset inout Outer o → v { = . o inner @ Inner { 2 ( vec_new [i] ) } }

@ fixed Outer b → i {
    : ~ Outer c ( mem_dup b )
    ( reset c )
    ^ . c n
}

@ broken Outer b → i {
    : ~ Outer c b
    ( reset c )
    ^ . c n
}

@ main → i {
    : Outer b @ Outer { 1 @ Inner { 1 ( vec_new [i] ) } }
    ^ + ( fixed b ) ( broken b )
}

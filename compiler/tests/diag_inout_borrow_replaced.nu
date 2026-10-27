// diag_inout_borrow_replaced.nu — an `inout` argument whose binding does
// not own its value, handed to a callee that gives that parameter (or a
// field of it) a new value (agora #135). The callee releases the old value,
// which is the owner's: a cursor's (`: ~ cur root`), a field read's, what
// arc_get lends — the owner then reads and drops it again. Each is refused
// at the call, the field of such a binding too, and one that borrows on
// one path only. A binding given a value of its own (`= cur ( vec_new )`,
// `( mem_dup … )`) may go, and so may a copy that holds the drop of the
// local it copies (inout_borrow_takeover) — but that local is moved by the
// call, and reading it after is a use of a moved value.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

: Holder { ( Vec i ) xs }

: Outer { Holder h }

@ reset_vec inout ( Vec i ) v → v { = v ( vec_new [i] ) }

@ reset inout Holder h → v { = . h xs ( vec_new [i] ) }

@ rename inout String s → v { = s ( string_from `a new name, long enough for a heap buffer` ) }

@ cursor → i {
    : ( Vec i ) root ( vec_new [i] )
    ( vec_push [i] root 5 )
    : ~ ( Vec i ) cur root
    ( reset_vec cur )
    ^ ( vec_len [i] root )
}

@ field_read Outer o → i {
    : ~ Holder h . o h
    ( reset h )
    ^ ( vec_len [i] . . o h xs )
}

@ field_of_a_borrow Outer o → i {
    : ~ Outer c o
    ( reset . c h )
    ^ ( vec_len [i] . . o h xs )
}

@ lent ( Arc String ) a → i {
    : ~ String s ( arc_get [String] a )
    ( rename s )
    ^ ( string_len ( arc_get [String] a ) )
}

@ one_path b c → i {
    : ( Vec i ) root ( vec_new [i] )
    ( vec_push [i] root 5 )
    : ~ ( Vec i ) cur root
    ? c { = cur ( vec_new [i] ) } {}
    ( reset_vec cur )
    ^ ( vec_len [i] root )
}

: Res { String name }

% Drop Res { @ drop Res r → v {} }

@ rename_res inout Res r → v { = . r name ( string_from `renamed` ) }

@ local_read_after → i {
    : Res s0 @ Res { ( string_from `local` ) }
    : ~ Res r s0
    ( rename_res r )
    ^ ( string_len . s0 name )
}

@ own_values Outer o → i {
    : ( Vec i ) root ( vec_new [i] )
    : ~ ( Vec i ) cur root
    = cur ( vec_new [i] )
    ( reset_vec cur )
    : ~ Holder h ( mem_dup . o h )
    ( reset h )
    ^ + ( vec_len [i] cur ) ( vec_len [i] . h xs )
}

@ main → i {
    : Outer o @ Outer { @ Holder { ( vec_new [i] ) } }
    : ( Arc String ) a ( arc_new [String] ( string_from `the shared name` ) )
    ^ + + + + + + ( cursor ) ( field_read o ) ( field_of_a_borrow o ) ( lent a ) ( one_path T ) ( own_values o ) ( local_read_after )
}

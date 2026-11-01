// string_param_viewed_into_a_local_holder_handed_on: agora #337 — string_param_viewed_through_self_recursion_into_a_local_holder without the recursion: a callee leaves a local holder viewing a String parameter and hands the holder on.
// Closed: what c7's recursion is checked against (agora #337).
// main: rejected.
// map: §2.10 | A2 | rejected | - | agora #337: a local holder given a String parameter's view, handed on to the caller's holder
$ `stdlib/core/string.nu`

: W { s v }

@ keep inout W w String a → v { = w @ W { ( string_data a ) } }

@ outer2 inout W w String a String b → v {
    : ~ W lh @ W { `x` }
    ( keep lh b )
    = w lh
}

@ main → i {
    : String o ( string_from `the outer string, which outlives the holder` )
    : ~ W w @ W { `literal` }
    {
        : String inner ( string_from `the inner string, freed at the end of its block` )
        ( outer2 w o inner )
    }
    ( nurl_println . w v )
    ^ 0
}

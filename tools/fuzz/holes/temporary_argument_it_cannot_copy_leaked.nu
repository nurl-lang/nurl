// temporary_argument_it_cannot_copy_leaked: a call's result that cannot be copied (a `% Drop` value with no clone) handed straight to another call — `( look ( mk ) )`, or through a function that hands its parameter back, `: Res r ( id ( mk ) )` — had no owner: the callee only read it (or lent it back), and nothing dropped it. A String temporary was dropped after the call, or moved into the result; this one leaked.
// Closed: such a temporary is dropped after the call unless the callee keeps it, and moves into the result when the callee hands it back.
// main (before this PR): LSan detected memory leaks.
// map: §7.1 | A2 | runs-clean | h234 | %Drop temporary passed to a borrowing call never dropped: leak
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mk → Res {
    ^ @ Res { ( vec_new [i] ) }
}

@ look Res r → i {
    ^ ( vec_len [i] . r buf )
}

@ id Res r → Res {
    ^ r
}

@ main → i {
    ( nurl_println_int ( look ( mk ) ) )
    : Res r ( id ( mk ) )
    ( nurl_println_int ( vec_len [i] . r buf ) )
    ^ 0
}

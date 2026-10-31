// option_of_a_value_it_cannot_copy_never_dropped: an option or result of a value that cannot be copied (a `?Res`, a `! Res E`, `Res` a `% Drop` value with no clone) was never dropped when bound — a local, a function's result, a temporary, a value replaced by `=` or handed to a `sink`: the payload and all it owned leaked. Only a struct field of that type was dropped (by its struct).
// Closed: such an option is registered through the same twin as an option of a String, so its binding drops its payload; a match arm's payload is a cursor over the binding (a payload moved out takes the option along), and over a parameter it is the caller's.
// main (before this PR): LSan detected memory leaks.
// map: §7.1 | A2 | runs-clean | h223 | option of %Drop value bound/replaced/discarded never dropped: leak
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ mk → ?Res {
    ^ @ ?Res { T @ Res { ( vec_new [i] ) } }
}

@ main → i {
    : ?Res p ( mk )
    : ~ ? Res q @ ?Res { T @ Res { ( vec_new [i] ) } }
    = q @ ?Res { F }
    ( mk )
    ^ 0
}

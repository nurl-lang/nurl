// result_error_it_cannot_copy_never_dropped: a result whose error cannot be copied (`! i Res`, `Res` a `% Drop` value with no clone) was never dropped when bound: an error it held leaked. Its Ok payload (h223) and a String error were owned; this error was not.
// Closed: such an error is owned through the same twin, dropped when the tag says it is there.
// main (before this PR): LSan detected memory leaks.
// map: §7.1 | A2 | runs-clean | h237 | result whose %Drop error is never dropped when bound: leak
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ fails → !i Res {
    ^ @ !i Res { F @ Res { ( vec_new [i] ) } }
}

@ main → i {
    : !i Res r ( fails )
    ^ 0
}

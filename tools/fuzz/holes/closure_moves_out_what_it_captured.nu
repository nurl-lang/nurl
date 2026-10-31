// closure_moves_out_what_it_captured: a closure body moving a value that cannot be copied (a `% Drop` value with no clone) out of its capture — into a literal, a container, a callee that keeps it — left the enclosing binding owning it too: `r` was released by the struct the closure made and again when `r`'s scope ended. Only a `sink` call or a release counted as the body taking the capture, and only for a String or a Vec.
// Closed: such a move takes the capture over — the enclosing binding no longer drops it, and a second use of the closure is a use after the move.
// main (before this PR): ASan heap-use-after-free.
// map: §7.5 | A2 | rejected | h222 | closure moves %Drop capture into a literal; frame drops it again
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ main → i {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ Hold ) f \ → Hold { @ Hold { r 1 } }
    : Hold a ( f )
    ( nurl_println_int . a n )
    : Hold b ( f )
    ^ 0
}

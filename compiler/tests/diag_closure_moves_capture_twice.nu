// A closure body that moves a value it cannot copy (a `% Drop` value with
// no clone) out of its capture — into a literal here — takes the capture
// over (h222): running it a second time would move a value already gone.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

: Hold { Res r i n }

@ main → i {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ Hold ) f \ → Hold { @ Hold { r 1 } }
    : Hold a ( f )
    : Hold b ( f )
    ^ 0
}

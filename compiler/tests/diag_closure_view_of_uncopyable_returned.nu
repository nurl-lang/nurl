// A closure capturing by value a value it cannot copy holds a view of the
// binding (h224): handed back inside a struct, it would outlive `r`.
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( nurl_println `drop` ) ( vec_free [i] . r buf ) }
}

: Box2 { ( @ i ) get }

@ mk → Box2 {
    : Res r @ Res { ( vec_new [i] ) }
    : ( @ i ) f \ → i { ( vec_len [i] . r buf ) }
    ^ @ Box2 { f }
}

@ main → i {
    : Box2 b ( mk )
    ^ 0
}

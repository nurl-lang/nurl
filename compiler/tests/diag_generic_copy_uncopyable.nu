// A generic that copies its T (box_clone, through mem_dup) cannot be
// instantiated with a value that cannot be copied (h235).
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v { ( vec_free [i] . r buf ) }
}

@ main → i {
    : ( Box Res ) b ( box_new [Res] @ Res { ( vec_new [i] ) } )
    : ( Box Res ) c ( box_clone [Res] b )
    ^ 0
}

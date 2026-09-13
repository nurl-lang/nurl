$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) values ( vec_new [i] )
    ; { ( vec_free [i] values ) }
    ; { ( vec_free [i] values ) }
    ^ 0
}

// A closure clears a Vec it captured: a capture by name the closure changes in place (`vec_clear`), the Vec measured after. nurlc compiles it; the checker refuses it.
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : ( @ v ) wipe \ → v { ( vec_clear [i] v ) }
    ( wipe )
    ^ ( vec_len [i] v )
}

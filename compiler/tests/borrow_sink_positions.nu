$ `stdlib/core/vec.nu`

@ second ( Vec i ) borrowed sink ( Vec i ) owned → i {
    ( vec_free [i] owned ) ^ ( vec_len [i] borrowed )
}

@ pair sink ( Vec i ) a sink ( Vec i ) b → v { ( vec_free [i] a ) ( vec_free [i] b ) }

@ main → i {
    : ( Vec i ) borrowed ( vec_new [i] )
    : ( Vec i ) owned ( vec_new [i] )
    ( second borrowed owned )
    ( vec_free [i] owned )
    : ( Vec i ) other ( vec_new [i] )
    ( pair borrowed other )
    ( vec_free [i] borrowed )
    ( vec_free [i] other )
    ^ 0
}

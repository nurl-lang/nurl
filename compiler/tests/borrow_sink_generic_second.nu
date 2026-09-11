$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec i ) borrowed ( vec_new [i] )
    : ( Vec i ) owned ( vec_new [i] )
    ( second [i] borrowed owned )
    ( vec_free [i] borrowed )
    ( vec_free [i] owned )
    ^ 0
}

@ second [A] ( Vec A ) borrowed ( Vec A ) owned → i {
    ( vec_free [A] owned ) ^ ( vec_len [A] borrowed )
}

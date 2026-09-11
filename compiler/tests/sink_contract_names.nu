// Function names and result types do not determine consuming positions.
$ `stdlib/core/vec.nu`

@ report_free ( Vec i ) values → v { ( nurl_println_int ( vec_len [i] values ) ) }

@ report_twice ( Vec i ) values → v { ( report_free values ) ( report_free values ) }

@ release_second ( Vec i ) borrowed sink ( Vec i ) owned → i {
    ( vec_free [i] owned )
    ^ ( vec_len [i] borrowed )
}

@ release_pair sink ( Vec i ) left sink ( Vec i ) right → v {
    ( vec_free [i] left ) ( vec_free [i] right )
}

@ main → i {
    : ( Vec i ) values ( vec_new [i] )
    ( vec_push [i] values 7 )
    ( report_twice values )
    ( nurl_println_int ( release_second values ( vec_new [i] ) ) )
    ( nurl_println_int ( late [i] values ( vec_new [i] ) ) )
    ( nurl_println_int ( vec_len [i] values ) )
    ( release_pair values ( vec_new [i] ) )
    ^ 0
}

@ late [A] ( Vec A ) borrowed ( Vec A ) owned → i {
    ( vec_free [A] owned )
    ^ ( vec_len [A] borrowed )
}

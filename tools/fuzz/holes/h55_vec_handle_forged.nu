// H55: a Vec handle forged by a struct literal from a String's raw view.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abc` )
    : ( Vec i ) xs @ ( Vec i ) { ( string_data t ) }
    ( nurl_println_int ( vec_len [i] xs ) )
    ^ 0
}

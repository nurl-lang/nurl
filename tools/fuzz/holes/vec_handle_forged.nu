// vec_handle_forged: a Vec handle forged by a struct literal from a String's raw view.
// map: §6.2 | B | rejected | h55 | Vec handle forged by struct literal from a String's raw view
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `abc` )
    : ( Vec i ) xs @ ( Vec i ) { ( string_data t ) }
    ( nurl_println_int ( vec_len [i] xs ) )
    ^ 0
}

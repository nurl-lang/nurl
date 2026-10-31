// user_wrapper_drops_elements: a user function empties a container (dropping elements) without releasing it.
// map: CallT.sink | A1 | rejected | h03 | String pushed (moved) into Vec, user fn clears Vec, original name read
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ wipe ( Vec String ) vs → v {
    ( vec_clear [String] vs )
}

@ main → i {
    : String a ( string_from `hello world, long enough to be heap` )
    : ( Vec String ) vs ( vec_new [String] )
    ( vec_push [String] vs a )
    ( wipe vs )
    ( nurl_println ( string_data a ) )
    ^ 0
}

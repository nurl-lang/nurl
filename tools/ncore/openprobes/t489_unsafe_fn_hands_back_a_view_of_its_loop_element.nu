// map: §2.10 | A2 | rejected | - | agora #489: an `unsafe` function hands back `( string_data x )` of its `~` loop's element over a parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ first ( Vec String ) p → s {
    ~ x p { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first t )
    ( vec_clear [String] t )
    ( nurl_println v )
    ^ 0
}

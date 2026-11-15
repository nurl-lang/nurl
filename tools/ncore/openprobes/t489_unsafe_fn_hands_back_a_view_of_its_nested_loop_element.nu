// map: §2.10 | A2 | rejected | - | agora #489: an `unsafe` function hands back a view of the inner `~` loop's element over rows of a parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

unsafe @ first ( Vec ( Vec String ) ) p → s {
    ~ row p {
        ~ x row { ^ ( string_data x ) }
    }
    ^ `none`
}

@ main → i {
    : ( Vec ( Vec String ) ) t ( vec_new [( Vec String )] )
    : ( Vec String ) row ( vec_new [String] )
    ( vec_push [String] row ( string_from `a string the caller clears before reading its view` ) )
    ( vec_push [( Vec String )] t row )
    : s v ( first t )
    ( vec_clear [( Vec String )] t )
    ( nurl_println v )
    ^ 0
}

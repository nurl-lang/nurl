// map: §2.10 | A2 | rejected | - | agora #489: an `unsafe` function hands back a view of its `~` loop's element over a struct parameter's field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rows { ( Vec String ) rows }

unsafe @ first Rows p → s {
    ~ x . p rows { ^ ( string_data x ) }
    ^ `none`
}

@ main → i {
    : Rows t @ Rows { ( vec_new [String] ) }
    ( vec_push [String] . t rows ( string_from `a string the caller clears before reading its view` ) )
    : s v ( first t )
    ( vec_clear [String] . t rows )
    ( nurl_println v )
    ^ 0
}

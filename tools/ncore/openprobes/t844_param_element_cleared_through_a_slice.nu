// map: §2.10 | A2 | rejected | - | agora #844: `( vec_clear ( slice_at sl 0 ) )` through a local Slice of a parameter's `( Vec ( Vec String ) )`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ ext ( Vec ( Vec String ) ) v → v {
    : ( Slice ( Vec String ) ) sl ( slice_from_vec [( Vec String )] v )
    ( vec_clear [String] ( slice_at [( Vec String )] sl 0 ) )
}

@ main → i {
    : ( Vec ( Vec String ) ) v ( vec_new [( Vec String )] )
    : ( Vec String ) row ( vec_new [String] )
    ( vec_push [String] row ( string_from `an element string long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] v row )
    : s view ( string_data ( vec_at [String] ( vec_at [( Vec String )] v 0 ) 0 ) )
    ( ext v )
    ( nurl_println view )
    ^ 0
}

// map: §2.10 | A2 | rejected | - | agora #844: `( slice_put sl 0 … )` through a local Slice of a parameter's Vec replaces (drops) the element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ ext ( Vec String ) v → v {
    : ( Slice String ) sl ( slice_from_vec [String] v )
    ( slice_put [String] sl 0 ( string_from `the replacement string, long enough for a heap buffer` ) )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : s view ( string_data ( vec_at [String] v 0 ) )
    ( ext v )
    ( nurl_println view )
    ^ 0
}

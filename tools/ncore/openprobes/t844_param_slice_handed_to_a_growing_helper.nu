// map: §2.10 | A2 | rejected | - | agora #844: a local Slice of a parameter's Vec handed to a helper that grows its element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow ( Slice String ) s → v {
    ( string_push_str ( slice_at [String] s 0 ) `a long text appended by the helper, long enough that the element's buffer has to move to a bigger allocation, and then some more text to be sure of it, well past any rounding of the first capacity` )
}

@ ext ( Vec String ) v → v {
    : ( Slice String ) sl ( slice_from_vec [String] v )
    ( grow sl )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : s view ( string_data ( vec_at [String] v 0 ) )
    ( ext v )
    ( nurl_println view )
    ^ 0
}

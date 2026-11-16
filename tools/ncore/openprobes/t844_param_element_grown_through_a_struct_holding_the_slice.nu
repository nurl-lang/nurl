// map: §2.10 | A2 | rejected | - | agora #844: an element grown through a struct holding a Slice of a parameter's Vec
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: SH { ( Slice String ) s }

@ ext ( Vec String ) v → v {
    : SH h @ SH { ( slice_from_vec [String] v ) }
    ( string_push_str ( slice_at [String] . h s 0 ) `a long text appended through the held slice, long enough that the element's buffer has to move to a bigger allocation, and then some more text to be sure of it, well past any rounding` )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : s view ( string_data ( vec_at [String] v 0 ) )
    ( ext v )
    ( nurl_println view )
    ^ 0
}

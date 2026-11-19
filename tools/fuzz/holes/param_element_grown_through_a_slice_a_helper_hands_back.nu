// map: §2.10 | A2 | rejected | - | agora #844: an element grown through a Slice of a parameter's Vec that a helper function hands back
// AGORA-844: refused - a slice of a parameter's Vec reaches the parameter's elements: what changes through it is in the function's drop summary (__pd_holds_storage; main f9356928: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ sl_of ( Vec String ) v → ( Slice String ) { ^ ( slice_from_vec [String] v ) }

@ ext ( Vec String ) v → v {
    : ( Slice String ) sl ( sl_of v )
    ( string_push_str ( slice_at [String] sl 0 ) `a long text appended through the slice, long enough that the element's buffer has to move to a bigger allocation, and then some more text to be sure of it, well past any rounding of the first capacity` )
}

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : s view ( string_data ( vec_at [String] v 0 ) )
    ( ext v )
    ( nurl_println view )
    ^ 0
}

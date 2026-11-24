// field_taken_through_a_viewer_then_pushed: a binding read out of a struct's field (`: R a . col res`) was handed to a `sink`, which takes the field over and leaves it empty where it lives. The field was then pushed through. A field handed to the sink directly was already refused (agora #280); through the viewer it was not.
// Closed: taking a field over through a binding read out of it moves the field, as handing the field directly does, until it is given a new value.
// main's compiler: compiled with no `unsafe`; vec_push stored through the emptied field's null handle (UB: the program re-entered main until the stack overflowed).
// map: §7.6 | A2 | rejected | h979 | field taken over through a viewer binding, then pushed through
$ `stdlib/core/vec.nu`

: R { ( Vec i ) v }
: C { R res i rc }

@ eat sink R r → i { ^ ( vec_len [i] . r v ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 41 )
    : ~ C col @ C { @ R { xs } 0 }
    : R a . col res
    ( nurl_println_int ( eat a ) )
    ( vec_push [i] . . col res v 5 )
    ( nurl_println_int ( vec_len [i] . . col res v ) )
    ^ 0
}

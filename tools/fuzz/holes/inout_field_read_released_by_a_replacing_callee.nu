// inout_field_read_released_by_a_replacing_callee: as h367, the binding read out of a struct's field (`: ~ Holder h . o h`) and the callee replacing a field of it: the Vec it released was o's.
// Closed: as h367 — a field read is a borrow of the field (bck_inout_borrow_check, agora #135).
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | h368 | as h367, the binding a field read and the callee replacing a field of it
$ `stdlib/core/vec.nu`

: Holder { ( Vec i ) xs }

: Outer { Holder h }

@ reset inout Holder h → v { = . h xs ( vec_new [i] ) }

@ main → i {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 )
    : Outer o @ Outer { @ Holder { v } }
    : ~ Holder h . o h
    ( reset h )
    ^ ( vec_len [i] . . o h xs )
}

// borrow_moved_cause_same_line.nu — the use-after-move diagnostic names
// the call that consumed the binding even when a later call on the same
// line reads it.
//
// `: i n ( give_away xs ) ^ + n ( vec_len [i] xs )` said "consumed at line
// N by vec_len": the read's own pending-call record took over the cause
// the consuming call had left for that line.

$ `stdlib/core/vec.nu`

@ give_away sink ( Vec i ) g → i { ^ ( vec_len [i] g ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    : i n ( give_away xs ) ^ + n ( vec_len [i] xs )
}

// vec_get_payload_field_handed_to_a_sink_then_read_again: `?? ( vec_get [Holder] vs 0 ) { T p → ( take . p buf ) }`, take a sink, then a second `vec_get` of the element pushes into `. q buf`: the take emptied the field in the Vec slot to a null handle, which the push dereferenced.
// Closed: a field of a payload a match lends (a vec_get payload, a user enum's payload) handed to a callee that takes it gets the callee a copy, where the callee consumes it (a declared sink, or the module-end consume answer), as a vec_at element does; the element keeps its own (agora #357).
// main 04a42b2a: accepted; SEGV.
// map: §7.6 | A2 | runs-clean | - | agora #357: a field of a lent match payload handed to a sink
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : ( Vec Holder ) vs ( vec_new [Holder] )
    ( vec_push [Holder] vs @ Holder { ( vec_new [u] ) } )
    ?? ( vec_get [Holder] vs 0 ) { T p → { : i n ( take . p buf ) } F _ → {} }
    ?? ( vec_get [Holder] vs 0 ) { T q → ( vec_push [u] . q buf # u 65 ) F _ → {} }
    ^ 0
}

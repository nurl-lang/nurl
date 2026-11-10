// enum_payload_field_handed_to_a_sink_then_matched_again: a user enum binding's payload field handed to a sink, then the enum matched again: the enum's own copy kept the buffer the callee freed, which the second match read and the enum's drop freed again.
// Closed: a field of a payload a match lends (a vec_get payload, a user enum's payload) handed to a callee that takes it gets the callee a copy, where the callee consumes it (a declared sink, or the module-end consume answer), as a vec_at element does; the element keeps its own (agora #357).
// main 04a42b2a: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #357: a field of a lent match payload handed to a sink
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }
: | Opt { Some Holder None }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : Opt o @ Opt { Some @ Holder { ( vec_new [u] ) } }
    ?? o { Some hh → { : i n ( take . hh buf ) } None → {} }
    ?? o { Some h2 → ( vec_push [u] . h2 buf # u 65 ) None → {} }
    ^ 0
}

// vec_field_taken_by_a_sink_then_pushed: agora #280 — a Vec field handed to a `sink`, then pushed to: the field was a null handle and vec_push faulted.
// main: accepted; the push dereferenced a null handle (SIGSEGV).
// map: §2.1 | A2 | rejected | - | agora #280: a Vec field handed to a `sink`, then pushed to: the field was a null handle and vec_push faulted
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ main → i {
    : Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : i n ( take . h buf )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}

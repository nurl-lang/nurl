// inout_field_taken_by_a_sink_then_used_by_the_caller: agora #280 — an `inout` callee hands a Vec field of its parameter to a `sink` and returns: the caller's struct comes back with a null handle, and its vec_push faulted.
// main: accepted; the caller's push dereferenced a null handle (SIGSEGV).
// map: §2.1 | A2 | rejected | - | agora #280: an `inout` callee hands a Vec field of its parameter to a `sink` and returns: the caller's struct comes back with a null handle, and its vec_push faulted
$ `stdlib/core/io.nu`
$ `stdlib/std/bytes.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ empty_it inout Holder h → v {
    : i n ( take . h buf )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    ( empty_it h )
    ( vec_push [u] . h buf # u 65 )
    ( nurl_println_int ( vec_len [u] . h buf ) )
    ^ 0
}

// taken_field_refilled_by_a_call_that_may_panic: AGORA-929 (CodeRabbit on github#2110) — the refill's own call may panic before its store: a `recover`ing caller gets `h` back with `buf` empty
// AGORA-939 (open): accepted by nurlc and ncore - the refill's own call is exempted until the walk knows which calls cannot panic (tools/fuzz/holes/open/t939.md)
// map: §2.1 | A2 | rejected | - | AGORA-929: an inout parameter's taken field refilled by a call that may panic
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ make_buf i k → ( Vec u ) {
    ? > k 2 { ( panic `unwind` ) } {}
    ^ ( vec_new [u] )
}

@ cycle inout Holder h i k → v {
    : i n ( take . h buf )
    = . h buf ( make_buf k )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}

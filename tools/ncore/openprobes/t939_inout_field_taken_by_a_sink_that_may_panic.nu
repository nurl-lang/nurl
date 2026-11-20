// t939_inout_field_taken_by_a_sink_that_may_panic: AGORA-939 (CodeRabbit on github#2110) — the sink that takes `. h buf` may itself panic: its argument is already handed over, so a `recover`ing caller gets `h` back with `buf` empty
// AGORA-939 (open): accepted by nurlc and ncore - the take's own call is not an unwind point for the field it takes until the walk knows which calls cannot panic (tools/fuzz/holes/open/t939.md)
// map: §2.1 | A2 | rejected | - | AGORA-939: an inout parameter's field taken by a sink call that may panic
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v i k → i {
    ? > k 2 { ( panic `unwind` ) } {}
    ^ ( vec_len [u] v )
}

@ cycle inout Holder h i k → v {
    : i n ( take . h buf k )
    = . h buf ( vec_new [u] )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    ( vec_push [u] . h buf # u 66 )
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}

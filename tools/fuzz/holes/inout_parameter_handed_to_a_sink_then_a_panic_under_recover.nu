// inout_parameter_handed_to_a_sink_then_a_panic_under_recover: `@ boom inout ( Vec S ) p → i { : i n ( eat p ) ( panic `boom` ) ^ n }` called under recover with a field target `( boom . h a )` and with a whole local; afterwards the struct and the local are dropped.
// Closed (agora #778): the field was emptied only when the call returned (#567), and a panic after the hand-over unwound past that step: h's drop released what eat had released. The function now empties its caller's slot itself, right where it hands its `inout` parameter to a consuming call, so the slot is empty on every path.
// main (before this PR): heap-use-after-free (SEGV) in h's drop during the unwind.
// map: §7.2 | A2 | runs-clean | - | an inout parameter handed to a sink, then a panic: the caller's field was released again by the unwind
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkv i k → ( Vec S ) {
    : ( Vec S ) v ( vec_new [S] )
    ( vec_push [S] v @ S { ( string_from `a name long enough to own a heap buffer` ) k } )
    ^ v
}

@ mkh → H { ^ @ H { ( mkv 1 ) ( mkv 2 ) } }

@ boom inout ( Vec S ) p → i {
    : i n ( eat p )
    ( panic `boom` )
    ^ n
}

@ main → i {
    : ~ H h ( mkh )
    : !v PanicInfo r ( recover \ → v { : i x ( boom . h a ) } )
    : ~ ( Vec S ) w ( mkv 3 )
    : !v PanicInfo r2 ( recover \ → v { : i y ( boom w ) } )
    ^ 0
}

// map: §2.1 | A2 | runs-clean | - | AGORA-939 guard: an inout parameter's field named by a value block, handed to a sink that may panic
// AGORA-939 guard: the block only lends `. h buf`, so `take` is given a copy and the field stays - accepted, and runs clean after recover (CodeRabbit on github#2129: ncore refused)
$ `stdlib/core/vec.nu`
$ `stdlib/std/panic.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v i k → i {
    ? > k 2 { ( panic `in the sink` ) } {}
    ^ ( vec_len [u] v )
}

@ cycle inout Holder h i k → v {
    : i n ( take { . h buf } k )
}

@ main → i {
    : ~ Holder h @ Holder { ( vec_new [u] ) }
    : !v PanicInfo r ( recover \ → v { ( cycle h 3 ) } )
    ( vec_push [u] . h buf # u 65 )
    ^ 0
}

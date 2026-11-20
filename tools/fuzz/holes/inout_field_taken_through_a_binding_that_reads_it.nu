// inout_field_taken_through_a_binding_that_reads_it: AGORA-929 (CodeRabbit on github#2110) — `: b . h buf` then `( take b )` in an `inout` function: moving the binding takes the field out of `h`, which goes back to the caller empty
// AGORA-929 (closed): refused by nurlc and ncore (main 0af1688b: accepted, a fault under ASan in the caller's push)
// map: §2.1 | A2 | rejected | - | AGORA-929: an inout parameter's field taken through a binding that reads it
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ g inout Holder h → v {
    : ( Vec u ) b . h buf
    : i k ( take b )
}

@ main → i { : ~ Holder h @ Holder { ( vec_new [u] ) } ( g h ) ( vec_push [u] . h buf # u 1 ) ^ 0 }

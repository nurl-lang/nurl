// taken_field_holder_returned_through_a_block_arm: AGORA-929 (CodeRabbit on github#2110) — `^ ? c { h } h2` after a sink took `. h buf`: the block-form arm hands `h` on with the field empty, where `^ ? c h h2` is refused
// AGORA-929 (closed): refused by nurlc and ncore (main 0af1688b: accepted, a fault under ASan in the caller's push)
// map: §2.1 | A2 | rejected | - | AGORA-929: a holder with a taken field handed on by a block-form join arm
$ `stdlib/core/vec.nu`

: Holder { ( Vec u ) buf }

@ take sink ( Vec u ) v → i { ^ ( vec_len [u] v ) }

@ f b c → Holder {
    : Holder h @ Holder { ( vec_new [u] ) }
    : Holder h2 @ Holder { ( vec_new [u] ) }
    : i k ( take . h buf )
    ^ ? c { h } h2
}

@ main → i { : Holder r ( f T ) ( vec_push [u] . r buf # u 1 ) ^ 0 }

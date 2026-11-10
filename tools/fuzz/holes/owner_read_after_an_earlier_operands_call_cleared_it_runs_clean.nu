// owner_read_after_an_earlier_operands_call_cleared_it_runs_clean: agora #577 — `+ ( cz fs ) ( vec_len fs )`: the owner itself is read after its elements were cleared
// Control for agora #577: a read that runs before the clearing call, and the owner read after it, are no reads of an ended borrow.
// map: §2.10 | A2 | runs-clean | - | agora #577: `+ ( cz fs ) ( vec_len fs )`: the owner itself is read after its elements were cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ two s a i b → i { ^ + ( nurl_str_len a ) b }

@ grow String l → i { : ~ i k 0 ~ < k 64 { ( string_push_str l ` and a long tail, so the buffer moves` ) = k + k 1 } ^ 0 }

@ main → i {
    : ( Vec String ) fs ( vec_new [String] )
    ( vec_push [String] fs ( string_from `a first string long enough for a heap buffer` ) )
    ( vec_push [String] fs ( string_from `a second string long enough for a heap buffer` ) )
    ( nurl_println_int + ( cz fs ) ( vec_len [String] fs ) )
    ^ 0
}

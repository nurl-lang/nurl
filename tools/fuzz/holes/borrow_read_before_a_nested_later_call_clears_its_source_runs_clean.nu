// borrow_read_before_a_nested_later_call_clears_its_source_runs_clean: agora #577 — `+ ( string_len s ) + ( cz fs ) 1`: s is read before the nested cz runs
// Control for agora #577: a read that runs before the clearing call, and the owner read after it, are no reads of an ended borrow.
// map: §2.10 | A2 | runs-clean | - | agora #577: `+ ( string_len s ) + ( cz fs ) 1`: s is read before the nested cz runs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ two s a i b → i { ^ + ( nurl_str_len a ) b }

@ grow String l → i { : ~ i k 0 ~ < k 64 { ( string_push_str l ` and a long tail, so the buffer moves` ) = k + k 1 } ^ 0 }

@ main → i {
    : ( Vec String ) fs ( vec_new [String] )
    ( vec_push [String] fs ( string_from `a first string long enough for a heap buffer` ) )
    ( vec_push [String] fs ( string_from `a second string long enough for a heap buffer` ) )
    : String s ( vec_at [String] fs 1 )
    ( nurl_println_int + ( string_len s ) + ( cz fs ) 1 )
    ^ 0
}

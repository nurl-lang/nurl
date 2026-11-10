// borrow_read_by_an_earlier_operand_before_a_later_operands_call_clears_its_source_runs_clean: agora #577 — `+ ( string_len s ) ( cz fs )`: s is read before cz runs
// Control for agora #577: a read that runs before the clearing call, and the owner read after it, are no reads of an ended borrow.
// map: §2.10 | A2 | runs-clean | - | agora #577: `+ ( string_len s ) ( cz fs )`: s is read before cz runs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ cz ( Vec String ) v → i { ( vec_clear [String] v ) ^ 0 }

@ main → i {
    : ( Vec String ) fs ( vec_new [String] )
    ( vec_push [String] fs ( string_from `a first string long enough for a heap buffer` ) )
    ( vec_push [String] fs ( string_from `a second string long enough for a heap buffer` ) )
    : String s ( vec_at [String] fs 1 )
    ( nurl_println_int + ( string_len s ) ( cz fs ) )
    ^ 0
}

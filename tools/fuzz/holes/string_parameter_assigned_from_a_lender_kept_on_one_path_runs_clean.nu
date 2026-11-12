// string_parameter_assigned_from_a_lender_kept_on_one_path_runs_clean: control: `= r ( f0 p )  ^ r` — the assignment copies the lend
// Closed: a `:` binding's lend out of a parameter the function takes over on another path is judged at `^` as the returned call is (agora #743): parked, refused at module end (__pfo_bind_lends, agora #765). A `: ~` binding is left as it was.
// main 9052104: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #765: control, a lend assigned (copied) then handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { String name i n }

@ f0 String p → String { ^ p }

@ f ( Vec String ) log String p b keep → String { ? keep { ( vec_push [String] log p ) ^ ( string_from `kept` ) } {} : ~ String r ( string_from `x` ) = r ( f0 p ) ^ r }

@ main → i {
    : ~ ( Vec String ) log ( vec_new [String] )
    : String a ( f log ( string_from `first value long enough for the heap buffer` ) F )
    ( nurl_println ( string_data a ) )
    : String x ( string_from `second value long enough for the heap buffer` )
    : String b ( f log x T )
    ( nurl_println ( string_data b ) )
    ^ 0
}

// drop_param_field_handed_back_while_kept_on_another_path_runs_clean: `^ . p s` out of a parameter of a struct with its own `% Drop`, which the function keeps on another path (`( vec_push log p )`): gen_ret moved the field out of p (zeroed), and R's destructor then ran on p and read the emptied field
// Closed: the field leaves and the struct keeps a copy of its own for its destructor (mem_field_copy_back), as an arm's `. q s` of its own struct does (agora #759).
// main 3c4322c: SEGV.
// map: §7.6 | A2 | runs-clean | - | agora #759: `^ . p s` out of a `% Drop` parameter kept on another path: the destructor read the zeroed field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ f ( Vec R ) log R p b keep → String {
    ? keep { ( vec_push [R] log p ) ^ ( string_from `kept` ) } {}
    ^ . p s
}

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : String a ( f log @ R { ( string_from `first value long enough for the heap buffer` ) 1 } F )
    ( nurl_println ( string_data a ) )
    : String b ( f log @ R { ( string_from `second value long enough for the heap buffer` ) 2 } T )
    ( nurl_println ( string_data b ) )
    ^ 0
}

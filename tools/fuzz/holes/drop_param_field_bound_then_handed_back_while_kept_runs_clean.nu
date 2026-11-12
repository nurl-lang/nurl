// drop_param_field_bound_then_handed_back_while_kept_runs_clean: as drop_param_field_handed_back_while_kept_on_another_path_runs_clean, the field bound first (`: String t . p s  ^ t`)
// Closed: as that probe (agora #759).
// main 3c4322c: AddressSanitizer: exit 1 (the destructor read a zeroed String).
// map: §7.6 | A2 | runs-clean | - | agora #759: `: String t . p s  ^ t` out of a `% Drop` parameter kept on another path
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

: W { String w }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ eat String x → v { ( nurl_println ( nurl_str_cat `ate ` ( string_data x ) ) ) }

@ f ( Vec R ) log R p b keep → String { ? keep { ( vec_push [R] log p ) ^ ( string_from `kept` ) } {} : String t . p s ^ t }

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : String a ( f log ( mk `first value long enough for the heap buffer` ) F )
    ( nurl_println ( string_data a ) )
    : String b ( f log ( mk `second value long enough for the heap buffer` ) T )
    ( nurl_println ( string_data b ) )
    ^ 0
}

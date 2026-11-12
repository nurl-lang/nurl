// renamed_drop_param_handed_to_a_keeper_defined_below_runs_clean: `: R q p` handed to a helper defined below that pushes it into a Vec: the parked implication (__fn_pending_sink_impl__) named q's index, none
// Closed: as renamed_drop_param_pushed_into_a_vec_is_consumed_runs_clean (agora #759).
// main 3c4322c: AddressSanitizer: heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | agora #759: `: R q p  ( g log q )`, g defined below keeps it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

: W { R r i k }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ eat sink R x → v { ( nurl_println ( nurl_str_cat `ate ` ( string_data . x s ) ) ) }

@ f ( Vec R ) log R p b keep → i { : R q p ? keep { ( g log q ) } {} ^ 1 }

@ g ( Vec R ) log R z → v { ( vec_push [R] log z ) }

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : i a ( f log ( mk `first value long enough for the heap buffer` ) F )
    : R x ( mk `second value long enough for the heap buffer` )
    : i b ( f log x T )
    ? > ( vec_len [R] log ) 0 { ( nurl_println ( string_data . ( vec_at [R] log 0 ) s ) ) } {}
    ^ 0
}

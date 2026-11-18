// struct_read_out_of_a_param_field_and_another_field_of_it_cleared_runs_clean: as struct_read_out_of_a_param_field_and_its_field_handed_to_a_clearing_callee, top clearing q.p.g while the caller views q.p.h.rows
// AGORA-495 guard: accepted - the edge is at q.p.g.rows, which the view does not reach
// map: §2.10 | A2 | runs-clean | - | AGORA-495
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) rows }
: P { H h H g }
: Q { P p }

@ wipe H h → v { ( vec_clear [String] . h rows ) }

@ top Q q → v { : P e . q p ( wipe . e g ) }

@ main → i {
    : ( Vec String ) r ( vec_new [String] )
    ( vec_push [String] r ( string_from `a heap string long enough to be on the heap for sure` ) )
    : Q q @ Q { @ P { @ H { r } @ H { ( vec_new [String] ) } } }
    : String v ( vec_at [String] . . . q p h rows 0 )
    ( top q )
    ( nurl_println ( string_data v ) )
    ^ 0
}

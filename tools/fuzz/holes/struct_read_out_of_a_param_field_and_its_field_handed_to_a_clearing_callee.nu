// struct_read_out_of_a_param_field_and_its_field_handed_to_a_clearing_callee: `: P e . q p  ( wipe . e h )` in top, the caller viewing an element of q.p.h.rows
// AGORA-495: refused - the binding keeps the path it was read at (q.p), so the drop edge is at q.p.h.rows (main 852f1f66: accepted, heap-use-after-free)
// map: §2.10 | A2 | rejected | - | AGORA-495
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) rows }
: P { H h }
: Q { P p }

@ wipe H h → v { ( vec_clear [String] . h rows ) }

@ top Q q → v { : P e . q p ( wipe . e h ) }

@ main → i {
    : ( Vec String ) r ( vec_new [String] )
    ( vec_push [String] r ( string_from `a heap string long enough to be on the heap for sure` ) )
    : Q q @ Q { @ P { @ H { r } } }
    : String v ( vec_at [String] . . . q p h rows 0 )
    ( top q )
    ( nurl_println ( string_data v ) )
    ^ 0
}

// struct_field_of_a_param_bound_and_handed_to_a_clearing_callee: `: H e . p h  ( wipe e )` in top, p a struct parameter, the caller viewing an element of p.h.rows
// AGORA-495: refused - the edge carries the field path (main: accepted, heap-use-after-free)
// map: §2.10 | A2 | rejected | - | AGORA-495
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ( Vec String ) rows ( Vec String ) names }
: P { H h }

@ wipe H h → v { ( vec_clear [String] . h rows ) }

@ look H h → i { ^ ( vec_len [String] . h rows ) }

@ top P p → v { : H e . p h ( wipe e ) }

@ main → i {
    : ( Vec H ) hs ( vec_new [H] )
    : ( Vec String ) r ( vec_new [String] )
    ( vec_push [String] r ( string_from `a heap string long enough to be on the heap for sure` ) )
    : ( Vec String ) nm ( vec_new [String] )
    ( vec_push [String] nm ( string_from `another heap string long enough to be on the heap for sure` ) )
    ( vec_push [H] hs @ H { r nm } )
    : P p @ P { ( vec_at [H] hs 0 ) }
    : String v ( vec_at [String] . . p h rows 0 )
    ( top p )
    ( nurl_println ( string_data v ) )
    ^ 0
}

// vec_at_copy_field_viewer_taken_then_vec_freed: as h394, through a binding read out of the copy's field, handed
// whole to `string_free`.
// Closed: as h394 (agora #145).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | h395 | as h394, through a field viewer of the copy taken whole
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ main → i {
    : ( Vec Q ) vs ( vec_new [Q] )
    ( vec_push [Q] vs @ Q { ( mk ) ( mk ) } )
    : Q e ( vec_at [Q] vs 0 )
    : String n . e name
    ( string_free n )
    ( vec_free [Q] vs )
    ^ 0
}

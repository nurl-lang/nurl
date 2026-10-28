// diag_field_handover_rejected.nu — a field handed to a callee that takes
// it, from a binding that cannot give it (agora #145). A parameter whose
// field the function hands on is taken (an inferred `sink`), so the
// caller's struct is moved; a vec_at copy, a binding read out of another's
// field and a closure's capture are emptied only in their own copy, while
// the owner still holds the field and releases it again.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Pair { String a String b }
: Outer { Pair p i n }

@ mk s t → String { ^ ( string_from t ) }

@ pair → Pair { ^ @ Pair { ( mk `alpha` ) ( mk `beta` ) } }

@ drop_a Pair p → v { ( string_free . p a ) }

@ caller_reads_after → v {
    : Pair q ( pair )
    ( drop_a q )
    ( nurl_println ( string_data . q b ) )
}

@ vec_at_copy → v {
    : ( Vec Pair ) vs ( vec_new [Pair] )
    ( vec_push [Pair] vs ( pair ) )
    : Pair e ( vec_at [Pair] vs 0 )
    ( string_free . e a )
    ( vec_free [Pair] vs )
}

@ vec_at_copy_viewer → v {
    : ( Vec Pair ) vs ( vec_new [Pair] )
    ( vec_push [Pair] vs ( pair ) )
    : Pair e ( vec_at [Pair] vs 0 )
    : String n . e a
    ( string_free n )
    ( vec_free [Pair] vs )
}

@ field_of_a_field_viewer → v {
    : Outer o @ Outer { ( pair ) 1 }
    : Pair e . o p
    ( string_free . e a )
}

@ field_of_a_capture → v {
    : Pair c ( pair )
    : ( @ v ) h \ → v { ( string_free . c a ) }
    ( h )
}

@ main → i { ^ 0 }

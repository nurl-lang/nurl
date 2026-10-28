// diag_closure_assigns_borrowed_capture_field.nu — a closure gives a field
// of a binding it captured by reference a new value (agora #144). The
// closure releases the value the field held under the binding's drop flag;
// a binding that only borrows its value — here a vec_at copy — has a struct
// that is its owner's, so the value stored would have no owner: rejected.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Pair { String a String b }

@ mk s t → String { ^ ( string_from t ) }

@ main → i {
    : ( Vec Pair ) vs ( vec_new [Pair] )
    ( vec_push [Pair] vs @ Pair { ( mk `alpha` ) ( mk `beta` ) } )
    : ~ Pair e ( vec_at [Pair] vs 0 )
    : ( @ v ) h \ → v { = . e b ( mk `gamma` ) }
    ( h )
    ( vec_free [Pair] vs )
    ^ 0
}

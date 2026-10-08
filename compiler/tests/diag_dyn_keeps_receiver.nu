// diag_dyn_keeps_receiver.nu — an impl that keeps its receiver, called
// through a trait object. The object owns the value and only lends it to
// the method: kept in the impl's Vec, it was dropped twice — once with
// the Vec, once with the object (a use after free before this check).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

% Named [T] {
    @ name T self → i
}

: Dog { String nm }

: Kennel { ( Vec Dog ) dogs }

% Named Dog { @ name Dog d → i { : Kennel k @ Kennel { ( vec_new [Dog] ) } ( vec_push [Dog] . k dogs d ) ^ ( vec_len [Dog] . k dogs ) } }

@ main → i {
    : Dog dg @ Dog { ( string_from `rex` ) }
    : %Named o ( dyn Named dg )
    ( nurl_print_int ( name o ) ) ( nurl_print `\n` )
    ^ 0
}

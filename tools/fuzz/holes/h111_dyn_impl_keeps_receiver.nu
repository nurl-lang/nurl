// H111: an impl that keeps its receiver, called through a trait object — the object still owns the value it lends the method, so the kept copy was dropped twice.
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

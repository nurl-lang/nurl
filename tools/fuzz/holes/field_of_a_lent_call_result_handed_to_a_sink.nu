// field_of_a_lent_call_result_handed_to_a_sink: a field of a call's lent result handed to `string_free` (`(
// string_free . ( box_get [Q] b ) name )`): the Box released the field
// again. A bare lent result handed to a `sink` is copied (h228); its field
// went over as is.
// Closed: a field of a call's result handed to a callee that takes it is a
// copy unless the field left with the read (the call handed its result
// over); one that cannot be copied is rejected (agora #150).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: CallT.sink | A1 | runs-clean | h424 | a field of box_get's lent result handed to string_free: the Box released it again (double free); such a field is handed over as a copy
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/core/rcbox.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ main → i {
    : ( Box Q ) b ( box_new [Q] @ Q { ( mk ) ( mk ) } )
    ( string_free . ( box_get [Q] b ) name )
    ( box_free [Q] b )
    ^ 0
}

// diag_owning_store_into_a_loop_element.nu — a field of a `~` loop's
// element given a value that owns memory (Agora #488). The loop binds a
// copy of each element: the store landed in that copy, the Vec kept its old
// value, and the new String was never released. Refused, naming the
// container-side ways to replace an element.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ main → i {
    : ( Vec P ) ps ( vec_new [P] )
    ( vec_push [P] ps @ P { ( string_from `old, a name long enough for a heap buffer` ) 1 } )
    ~ p ps {
        = . p name ( string_from `new, a name long enough for a heap buffer` )
    }
    ^ 0
}

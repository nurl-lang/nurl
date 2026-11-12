// Three readers of one field, then the field replaced: the first reader
// owns the old value; once it is handed over, the third, a view of that
// value, is gone — reading it is rejected (agora #387).
$ `stdlib/core/string.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : String g1 . o name
    : String g2 . o name
    : String g3 . o name
    = . o name ( string_from `the new name long enough for the heap` )
    ( gone g1 )
    ( nurl_println ( string_data g3 ) )
    ^ 0
}

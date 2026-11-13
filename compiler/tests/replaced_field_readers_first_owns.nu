// Three readers of one field, then the field replaced: the first reader
// owns the old value (it may be handed over), the later two are views of
// it, read before that (agora #387). The two #354 shapes stay clean.
$ `stdlib/core/string.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : String g1 . o name
    : String g2 . o name
    : String g3 . o name
    = . o name ( string_from `the new name long enough for the heap` )
    ( nurl_println ( string_data g3 ) )
    ( nurl_println ( string_data g2 ) )
    ( gone g1 )
    ^ 0
}

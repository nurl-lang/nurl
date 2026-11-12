// An outer and an inner reader of one field, the field replaced in the
// inner scope: the outer one owns the old value and may be handed over
// after the inner one goes (agora #387).
$ `stdlib/core/string.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : String outer . o name
    {
        : String inner . o name
        = . o name ( string_from `the new name long enough for the heap` )
        ( nurl_println ( string_data inner ) )
    }
    ( gone outer )
    ^ 0
}

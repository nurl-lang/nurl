// Two readers of one field bound in a loop body, the field replaced, the
// second handed to a sink: it is a view of the value the first owns, so it
// is rejected, on every round (agora #387).
$ `stdlib/core/string.nu`

: O { String name }

@ gone sink String s → v {}

@ main → i {
    : ~ O o @ O { ( string_from `the old name long enough for the heap` ) }
    : ~ i k 0
    ~ < k 3 {
        : String g1 . o name
        : String g2 . o name
        = . o name ( string_from `a newer name long enough for the heap` )
        ( gone g2 )
        = k + k 1
    }
    ^ 0
}

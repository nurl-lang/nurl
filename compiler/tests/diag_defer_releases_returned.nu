// diag_defer_releases_returned.nu — a `;` defer that releases the value a
// return hands back (agora #165), armed for certain, in a loop, or giving
// a field of the returned struct a new value: the defers run after the
// value is the caller's.

$ `stdlib/core/string.nu`

: Q { String name String tag }

@ mk s t → String { ^ ( string_from t ) }

@ frees_it → String {
    : String s ( mk `one` )
    ; { ( string_free s ) }
    ^ s
}

@ in_a_loop → String {
    : String s ( mk `two` )
    : ~ i k 0
    ~ < k 1 { ; { ( string_free s ) } = k + k 1 }
    ^ s
}

@ replaces_a_field → Q {
    : ~ Q q @ Q { ( mk `three` ) ( mk `four` ) }
    ; { = . q name ( mk `five` ) }
    ^ q
}

@ main → i { ^ 0 }

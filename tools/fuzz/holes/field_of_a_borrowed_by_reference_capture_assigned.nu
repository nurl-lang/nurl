// field_of_a_borrowed_by_reference_capture_assigned: as h405, the captured binding a vec_at copy: the struct is the
// Vec's, so the value the closure stored had no owner.
// Closed: a closure that gives a field of a by-pointer capture a new value
// is rejected unless the binding owns its value (agora #144).
// v0.80.0: accepted; LeakSanitizer reported memory leaks.
// map: §2.11 | A2 | rejected | h406 | as h405, the binding a vec_at copy: the stored value had no owner (leak); rejected unless the binding owns its value
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: Q { String name String tag }

@ main → i {
    : ( Vec Q ) vs ( vec_new [Q] )
    ( vec_push [Q] vs @ Q { ( mk ) ( mk ) } )
    : ~ Q q ( vec_at [Q] vs 0 )
    : ( @ v ) h \ → v { = . q tag ( mk ) }
    ( h )
    ( nurl_println ( string_data . q tag ) )
    ( vec_free [Q] vs )
    ^ 0
}

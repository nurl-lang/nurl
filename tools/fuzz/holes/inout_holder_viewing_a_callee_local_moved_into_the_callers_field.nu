// inout_holder_viewing_a_callee_local_moved_into_the_callers_field: the same as the _returns probe, falling off the callee's end instead of `^` (PO probe r39b).
// Closed: as its _returns twin (agora #381). Refused on main 9e8d4a88.
// main d85806eb / 8a2afbc: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #381: an inout holder viewing a callee local moved into the caller's inout field, at the body's end
$ `stdlib/core/string.nu`

: W { s v }
: K { String keep }

@ fill inout W w inout K h → v {
    : String b ( string_from `the callee's local string, moved into the caller's field` )
    = w @ W { ( string_data b ) }
    = . h keep b
}

@ main → i {
    : ~ W w @ W { `literal` }
    : ~ K h @ K { ( string_from `the caller's first keep, long enough for heap` ) }
    ( fill w h )
    = . h keep ( string_from `the caller's second keep, long enough for heap` )
    ( nurl_println . w v )
    ^ 0
}

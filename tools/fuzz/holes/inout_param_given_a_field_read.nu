// inout_param_given_a_field_read: an `inout` parameter given a binding read out of a field (`: String z . r name` … `= y z`) stored the field's buffer as is: the caller's binding and the struct both owned it, and the value `y` held leaked.
// Closed: an `inout` parameter given any binding that does not own its value outright — a parameter it only borrows (h201), a field read, a closure's capture — is given a copy, and the value it held is dropped.
// v0.78.0: accepted; ASan reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | h345 | an inout parameter given a binding read out of a field stored the field's buffer as is (two owners); it is given a copy, and the value it held is dropped
$ `stdlib/core/string.nu`

: Rec { String name }

@ put inout String y Rec r → v {
    : String z . r name
    = y z
}

@ main → i {
    : Rec r @ Rec { ( string_from `a field string long enough to own a heap buffer` ) }
    : ~ String x ( string_from `the old value, long enough to own a buffer too` )
    ( put x r )
    ( nurl_println ( string_data x ) )
    ( nurl_println ( string_data . r name ) )
    ^ 0
}

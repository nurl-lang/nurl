// An `inout` parameter given a binding whose value another owner keeps —
// a field read (h345), a closure's capture (h346), a parameter the
// function only borrows (h201) — gets a copy, and the value it held is
// dropped; a closure's `inout` parameter given a fresh value keeps it for
// the caller (h347).
$ `stdlib/core/string.nu`

: Rec { String name }

@ from_field inout String y Rec r → v {
    : String z . r name
    = y z
}

@ from_param inout String y String b → v { = y b }

@ apply ( @ v inout String ) f inout String x → v { ( f x ) }

@ main → i {
    : Rec r @ Rec { ( string_from `the field's string, long enough to own a buffer` ) }
    : String b ( string_from `a borrowed string, long enough to own a buffer` )
    : ~ String x ( string_from `the old value, long enough to own a buffer too` )
    ( from_field x r )
    ( nurl_println ( string_data x ) )
    ( from_param x b )
    ( nurl_println ( string_data x ) )
    ( apply \ inout String y → v { = y b } x )
    ( nurl_println ( string_data x ) )
    ( apply \ inout String y → v { = y ( string_from `a fresh string, long enough to own a buffer` ) } x )
    ( nurl_println ( string_data x ) )
    ( nurl_println ( string_data . r name ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}

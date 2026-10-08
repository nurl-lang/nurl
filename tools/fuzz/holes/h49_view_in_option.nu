// H49: a string view wrapped in an Option; the String is freed; the payload is read.
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `a long string whose view goes into an option` )
    : ?s o @ ?s { T ( string_data t ) }
    ( string_free t )
    ?? o { T p → { ( nurl_println p ) } F → {} }
    ^ 0
}

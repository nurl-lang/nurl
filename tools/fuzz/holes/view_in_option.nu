// view_in_option: a string view wrapped in an Option; the String is freed; the payload is read.
// map: §2.12 | A2 | rejected | h49 | string view wrapped in an Option; String freed; payload read
$ `stdlib/core/string.nu`

@ main → i {
    : String t ( string_from `a long string whose view goes into an option` )
    : ?s o @ ?s { T ( string_data t ) }
    ( string_free t )
    ?? o { T p → { ( nurl_println p ) } F → {} }
    ^ 0
}

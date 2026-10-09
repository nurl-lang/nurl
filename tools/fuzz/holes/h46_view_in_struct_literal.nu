// H46: a string view is stored in a struct literal; the String is freed; the field is read.
$ `stdlib/core/string.nu`

: Hold { s p i n }

@ main → i {
    : String t ( string_from `a long string whose view goes into a struct` )
    : Hold h @ Hold { ( string_data t ) 1 }
    ( string_free t )
    ( nurl_println . h p )
    ^ 0
}

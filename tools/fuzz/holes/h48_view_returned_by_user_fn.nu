// H48: a user function returns a view of its parameter; the String is freed; the view is read.
$ `stdlib/core/string.nu`

@ view String t → s { ^ ( string_data t ) }

@ main → i {
    : String t ( string_from `a long string whose view is returned by a helper` )
    : s p ( view t )
    ( string_free t )
    ( nurl_println p )
    ^ 0
}

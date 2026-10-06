// H8 (leak): a pre-defer owned value returned on one path but not another.
$ `stdlib/core/string.nu`

@ pick b c → String {
    : String a ( string_from `leaky string value that is heap allocated` )
    ; { ( nurl_print `` ) }
    ? c { ^ a } {}
    ^ ( string_from `other` )
}

@ main → i {
    : String x ( pick F )
    ( nurl_println ( string_data x ) )
    ^ 0
}

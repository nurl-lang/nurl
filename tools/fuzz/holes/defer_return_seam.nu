// defer_return_seam (leak): a pre-defer owned value returned on one path but not another.
// map: §7.1 | A2 | runs-clean | h08 | owned value before a defer returned on one path only (leak)
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

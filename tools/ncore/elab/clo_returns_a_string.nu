// A closure that hands back a fresh String, measured by its caller.
$ `stdlib/core/string.nu`

@ main → i {
    : ( @ String i ) make \ i n → String { ^ ( string_from `made by a closure` ) }
    : String s ( make 1 )
    ^ ( string_len s )
}

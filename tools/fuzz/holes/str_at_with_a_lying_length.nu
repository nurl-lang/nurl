// str_at_with_a_lying_length: nurl_str_at trusted a length longer than the string and read past its block.
// map: §6.4 | B | rejected | h99 | nurl_str_at trusts a length longer than the string
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `abc` )
    : ~ i t 0
    : ~ i k 0
    ~ < k 4096 { = t + t ( nurl_str_at ( string_data a ) 4096 k ) = k + k 1 }
    ( nurl_println_int t )
    ^ 0
}

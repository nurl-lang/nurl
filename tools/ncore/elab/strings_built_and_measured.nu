// Strings made from literals and from other text, their lengths read.
$ `stdlib/core/string.nu`

@ main → i {
    : String a ( string_from `abc` )
    : s t ( nurl_str_cat `x` `yz` )
    : s u ( nurl_str_cat t `w` )
    ^ + + ( string_len a ) ( nurl_str_len t ) ( nurl_str_len u )
}

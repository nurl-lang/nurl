// Test: an index found in a temporary's text (agora #323). nurl_str_find
// returns `- # i p # i haystack`, a distance. The difference was taken to
// carry the haystack's address, so the function was summarised as handing
// back its argument (`ret_param 0`): a temporary String's view handed to
// it was refused as "kept past the call", and one kept alive was never
// freed. A subtraction hands on only its left operand's address.
$ `stdlib/core/string.nu`

@ main → i {
    : i k ( nurl_str_find ( string_data ( string_from `a temporary string long enough for the heap` ) ) `long` )
    ( nurl_println_int k )
    : i j ( nurl_str_find_from ( string_data ( string_from `find the second find in this temporary` ) ) 1 `find` )
    ( nurl_println_int j )
    ^ 0
}

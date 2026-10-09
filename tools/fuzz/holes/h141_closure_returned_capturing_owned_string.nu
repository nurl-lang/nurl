// H141: a closure literal handed back that captured an owned local string: the string was released on the way out, and every call of the closure read freed memory (a returned closure or literal was not checked for what its views point into).
$ `stdlib/core/string.nu`

@ mk s a → ( @ i ) {
    : s x ( nurl_str_cat a `bc` )
    ^ \ → i { ^ ( nurl_str_len x ) }
}

@ main → i {
    : ( @ i ) f ( mk `x` )
    ( nurl_print_int ( f ) ) ( nurl_print `\n` )
    ^ 0
}

// H135: the H134 leak over a field built with a view of a String.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

@ main → i {
    : String t ( string_from `view` )
    : ~ Rec r @ Rec { ( string_data t ) 1 }
    = . r name ( nurl_str_cat `c` `de` )
    ( nurl_print . r name ) ( nurl_print `\n` )
    ^ 0
}

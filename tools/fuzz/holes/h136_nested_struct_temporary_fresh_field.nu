// H136: the H129 temporary with the struct nested in another: the nested raw string field leaked.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Rec { s name i n }

: Outer { Rec r i k }

@ g Outer o → i { ^ ( nurl_str_len . . o r name ) }

@ main → i {
    ( nurl_print_int ( g @ Outer { @ Rec { ( nurl_str_cat `a` `bc` ) 1 } 2 } ) ) ( nurl_print `\n` )
    ^ 0
}

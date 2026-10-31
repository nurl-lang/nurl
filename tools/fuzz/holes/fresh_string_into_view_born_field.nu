// fresh_string_into_view_born_field: the H134 leak over a field built with a view of a String.
// map: §2.13 | A2 | rejected | h135 | fresh string assigned to view-born s field leaks
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

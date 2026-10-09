// H127: a view stored into an owned field, the struct handed back: the caller read — and freed — a String the callee had dropped on the way out.
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ make → Rec {
    : String t ( string_from `view` )
    : ~ Rec r @ Rec { ( nurl_str_cat `a` `b` ) 1 }
    = . r name ( string_data t )
    ^ r
}

@ main → i {
    : Rec q ( make )
    ( nurl_print . q name ) ( nurl_print `\n` )
    ^ 0
}

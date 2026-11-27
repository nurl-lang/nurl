// A struct's String field grown through a borrow of it, then viewed and measured.
$ `stdlib/core/string.nu`

: N { String name i n }

@ main → i {
    : String s ( string_from `ab` )
    : N x @ N { s 2 }
    ( string_push_str . x name `cd` )
    : s v ( string_data . x name )
    ^ + ( nurl_str_len v ) ( string_len . x name )
}

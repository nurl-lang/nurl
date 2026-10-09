// H122: a mutable string born from a struct's field had no owner slot, so the owned strings assigned to it after leaked, one per assignment.
$ `stdlib/core/string.nu`

: Rec { s name i n }

@ main → i {
    : Rec r @ Rec { `abc` 1 }
    : ~ s p . r name
    : ~ i k 0
    ~ < k 3 {
        = p ( nurl_str_cat `x` ( nurl_str_int k ) )
        = k + k 1
    }
    ( nurl_print_int ( nurl_str_len p ) ) ( nurl_print `\n` )
    ^ 0
}

// diag_string_len_on_cstr.nu — the mirror of diag_str_len_on_string:
// 'string_len' handed a raw C-string literal.
$ `stdlib/core/string.nu`

@ main → i {
    : i n ( string_len `hi` )
    ^ n
}

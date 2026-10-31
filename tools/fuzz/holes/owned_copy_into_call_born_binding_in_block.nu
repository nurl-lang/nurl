// owned_copy_into_call_born_binding_in_block: the H119 leak from a block: the tracked local ends with the block, the copy given to the outer binding was owned by nobody.
// map: §7.6 | A2 | runs-clean | h120 | owned copy assigned to view-born binding from a block leaks
$ `stdlib/core/string.nu`

@ main → i {
    : String base ( string_from `base` )
    : ~ s y ( string_data base )
    {
        : s x ( nurl_str_cat `ab` `cd` )
        = y x
    }
    = y `lit`
    ( nurl_print_int ( nurl_str_len y ) ) ( nurl_print `\n` )
    ^ 0
}

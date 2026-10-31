// owned_copy_into_call_born_binding: a mutable string born from a call that never hands its result over (a view) had no owner slot, so a tracked local assigned to it — copied, as it must be — leaked the copy, once per iteration.
// map: §7.6 | A2 | runs-clean | h119 | owned copy assigned to view-born mutable s binding leaks per iteration
$ `stdlib/core/string.nu`

@ main → i {
    : String base ( string_from `base` )
    : ~ s y ( string_data base )
    : ~ i k 0
    ~ < k 3 {
        : s x ( nurl_str_cat `ab` `cd` )
        = y x
        = k + k 1
    }
    ( nurl_print_int ( nurl_str_len y ) ) ( nurl_print `\n` )
    ^ 0
}

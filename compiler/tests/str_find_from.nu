// str_find_from.nu — nurl_str_find_from: the first match at or after an
// offset, as an index into the whole haystack; -1 past the last match or
// for an offset outside [0, len].

$ `stdlib/core/string.nu`

@ main → i {
    : s h `abcabcab`
    ( nurl_println_int ( nurl_str_find_from h 0 `abc` ) )  // 0
    ( nurl_println_int ( nurl_str_find_from h 1 `abc` ) )  // 3
    ( nurl_println_int ( nurl_str_find_from h 4 `abc` ) )  // -1
    ( nurl_println_int ( nurl_str_find_from h 6 `ab` ) )  // 6
    ( nurl_println_int ( nurl_str_find_from h 8 `` ) )  // 8 (empty needle at the end)
    ( nurl_println_int ( nurl_str_find_from h 9 `a` ) )  // -1 (past the end)
    ( nurl_println_int ( nurl_str_find_from h -1 `a` ) )  // -1 (negative)
    // every match, stepping past each
    : ~ i k 0
    : ~ i n 0
    ~ >= k 0 {
        = k ( nurl_str_find_from h k `ab` )
        ? >= k 0 { = n + n 1 = k + k 1 } {}
    }
    ( nurl_println_int n )  // 3
    ^ 0
}

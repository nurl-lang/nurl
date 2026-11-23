// map: §7.6 | A2 | rejected | - | AGORA-953: a `% Drop` value an inner block's join lends out of a field (`: D e ? c dd @ D { … }`, dd a view of `. q d`), bound by `:` then assigned outward: no copy to give, refused as `= od ? c dd …` is
// Was a heap-use-after-free under ASan on main 3f08626.
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

: Q { String s D d }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ~ D od @ D { ( mk ) }
    : b c > ( string_len . od s ) 3
    ? c {
        : Q q @ Q { ( mk ) @ D { ( mk ) } }
        : D dd . q d
        : D e ? c dd @ D { ( mk ) }
        = od e
    } {}
    ( nurl_println_int ( string_len . od s ) )
    ^ 0
}

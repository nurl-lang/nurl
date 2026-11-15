// map: §7.6 | A2 | runs-clean | - | agora #846: `= a { : ( @ i i ) h \ … h }` while a `;` defer that calls `a` is armed
$ `stdlib/core/string.nu`

@ main → i {
    : String tag ( string_from `a captured tag long enough for a heap buffer` )
    : ~ ( @ i i ) a \ i x → i { ^ + x ( string_len tag ) }
    ; { ( nurl_println_int ( a 1 ) ) }
    = a { : ( @ i i ) h \ i x → i { ^ + + x 2 ( string_len tag ) } h }
    ( nurl_println_int ( a 1 ) )
    ^ 0
}

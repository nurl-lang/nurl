// map: §7.6 | A2 | rejected | - | agora #851: `\ → i { = . . o inner name ( string_from … ) … }`, o a by-value capture: an owning value stored through a nested field path into the capture leaks
$ `stdlib/core/string.nu`

: In { String name i k }

: Out { In inner i n }

@ main → i {
    : Out o @ Out { @ In { ( string_from `an original name long enough to live on the heap` ) 1 } 2 }
    : ( @ i ) f \ → i { = . . o inner name ( string_from `a replacement name long enough to live on the heap` ) ^ . o n }
    ( nurl_println_int ( f ) )
    ( nurl_println ( string_data . . o inner name ) )
    ^ 0
}

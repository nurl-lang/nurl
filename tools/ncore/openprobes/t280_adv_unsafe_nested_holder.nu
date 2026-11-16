// map: §2.14 | A2 | rejected | - | agora #280: adversarial neighbour of the destructor-as-effect rule (a280_unsafe_nested_holder)
$ `stdlib/core/string.nu`

: Named { String s i n }
: Outer { Named m i z }

% Drop Named { @ drop Named c → v { ( string_push_str . c s `, dropped` ) ( nurl_println ( string_data . c s ) ) } }

@ eat sink String v → i { ^ ( string_len v ) }

@ main → i {
    : Outer o @ Outer { @ Named { ( string_from `a name long enough to own a heap buffer of its own` ) 1 } 2 }
    : i k ( eat . . o m s )
    ^ 0
}

// map: §7.6 | A2 | rejected | - | agora #851: `~ c cs { : String s …  = . c f \ → i { … s … } }`: a capturing closure stored into a loop element's field leaks its environment
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: C { ( @ i ) f i n }

@ main → i {
    : ( Vec C ) cs ( vec_new [C] )
    ( vec_push [C] cs @ C { \ → i { ^ 2 } 1 } )
    ~ c cs {
        : String s ( string_from `captured string long enough for the heap` )
        = . c f \ → i { ^ ( string_len s ) }
    }
    ( nurl_println_int ( vec_len [C] cs ) )
    ^ 0
}

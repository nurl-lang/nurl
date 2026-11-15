// map: §7.6 | A2 | rejected | - | agora #851: `~ p os { = . . p inner name ( string_from … ) }`: an owning value stored through a nested field path into a `~` loop element leaks
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: In { String name i k }

: Out { In inner i n }

@ main → i {
    : ( Vec Out ) os ( vec_new [Out] )
    ( vec_push [Out] os @ Out { @ In { ( string_from `an original name long enough to live on the heap` ) 1 } 2 } )
    ~ p os { = . . p inner name ( string_from `a replacement name long enough to live on the heap` ) }
    ( nurl_println ( string_data . . ( vec_at [Out] os 0 ) inner name ) )
    ^ 0
}

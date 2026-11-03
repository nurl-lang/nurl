// closure_hands_back_what_it_takes_or_builds_runs_clean: a closure hands back an element it pops out of its captured Vec, and another builds a fresh value from a captured element's data.
// Must keep compiling and running clean beside agora #446's rule.
// main's compiler: compiled, ran clean.
// map: §2.3 | A2 | runs-clean | - | agora #446: a closure hands back an element it pops out of its captured Vec, and another builds a fresh value from a captured element's data
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

@ main → i {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `an element name long enough to live on the heap for sure` ) } )
    ( vec_push [Conn] cs @ Conn { ( string_from `a second element name long enough to live on the heap` ) } )
    : ( @ Conn ) take \ → Conn {
        ?? ( vec_pop [Conn] cs ) {
            T c → { ^ c }
            F → {}
        }
        ^ @ Conn { ( string_from `fresh` ) }
    }
    : ( @ Conn ) copy \ → Conn {
        : Conn c @ Conn { ( string_from ( string_data . ( vec_at [Conn] cs 0 ) name ) ) }
        ^ c
    }
    : Conn a ( take )
    : Conn b ( copy )
    ( nurl_println ( string_data . a name ) )
    ( nurl_println ( string_data . b name ) )
    ^ 0
}

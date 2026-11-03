// closure_returns_a_vec_get_payload_of_its_own_vec_runs_clean: a `vec_get` payload of the body's own Vec, handed back: taken out of its slot.
// Must keep compiling and running clean beside agora #372's rule.
// main's compiler: compiled, ran clean.
// map: §7.6 | A2 | runs-clean | - | agora #372: a `vec_get` payload of the body's own Vec, handed back: taken out of its slot
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

@ main → i {
    : ( @ Conn ) f \ → Conn {
        : ( Vec Conn ) cs ( vec_new [Conn] )
        ( vec_push [Conn] cs @ Conn { ( string_from `an element name long enough to live on the heap for sure` ) } )
        ?? ( vec_get [Conn] cs 0 ) { T e → { ^ e } F → { ^ @ Conn { ( string_from `none` ) } } }
    }
    : Conn a ( f )
    ^ 0
}

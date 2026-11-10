// lent_element_handed_back_then_its_vec_cleared: agora #462 — the j12 result read after the caller clears cs: it is a lend of cs
// Control for agora #462: refused on main too.
// map: §2.10 | A2 | rejected | - | agora #462: the j12 result read after the caller clears cs: it is a lend of cs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name i fd }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . c name ) ) ) } }

@ g ( Vec Conn ) cs → Conn { : Conn c ( vec_at [Conn] cs 0 ) ^ c }

@ main → i {
    : ( Vec Conn ) cs ( vec_new [Conn] )
    ( vec_push [Conn] cs @ Conn { ( string_from `the first connection, a heap name` ) 3 } )
    : Conn a ( g cs )
    ( vec_clear [Conn] cs )
    ( nurl_println ( string_data . a name ) )
    ^ 0
}

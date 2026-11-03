// closure_returns_a_join_binding_of_its_own_vec_element: a binding of a `?` whose arm is an element of the body's own Vec, handed back.
// Closed: a closure body's `^` of a binding a call may lend — an element of the body's own Vec, of a capture, or a binding of a join one of whose arms is such a call — is judged as that call is, whole (resolve_clo_nc_rets): refused when the callee may lend and the type cannot be copied, as a function's local-lend rule refuses it (agora #372).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #372: a binding of a `?` whose arm is an element of the body's own Vec, handed back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

@ main → i {
    : ( @ Conn b ) f \ b k → Conn {
        : ( Vec Conn ) cs ( vec_new [Conn] )
        ( vec_push [Conn] cs @ Conn { ( string_from `an element name long enough to live on the heap for sure` ) } )
        : Conn c ? k ( vec_at [Conn] cs 0 ) @ Conn { ( string_from `fresh` ) }
        ^ c
    }
    : Conn a ( f T )
    ^ 0
}

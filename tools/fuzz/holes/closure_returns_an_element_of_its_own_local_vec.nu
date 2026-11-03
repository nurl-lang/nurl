// closure_returns_an_element_of_its_own_local_vec: a closure hands back `: Conn c ( vec_at [Conn] cs 0 )` of a Vec it drops on the way out; the element is dropped twice.
// Closed: a closure body's `^` of a binding a call may lend — an element of the body's own Vec, of a capture, or a binding of a join one of whose arms is such a call — is judged as that call is, whole (resolve_clo_nc_rets): refused when the callee may lend and the type cannot be copied, as a function's local-lend rule refuses it (agora #372).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #372: a closure hands back `: Conn c ( vec_at [Conn] cs 0 )` of a Vec it drops on the way out; the element is dropped twice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Conn { String name }

% Drop Conn { @ drop Conn c → v { ( nurl_println ( string_data . c name ) ) } }

@ main → i {
    : ( @ Conn ) f \ → Conn {
        : ( Vec Conn ) cs ( vec_new [Conn] )
        ( vec_push [Conn] cs @ Conn { ( string_from `an element name long enough to live on the heap for sure` ) } )
        : Conn c ( vec_at [Conn] cs 0 )
        ^ c
    }
    : Conn a ( f )
    ^ 0
}

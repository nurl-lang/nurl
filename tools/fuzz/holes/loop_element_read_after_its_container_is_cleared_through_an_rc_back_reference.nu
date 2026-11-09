// loop_element_read_after_its_container_is_cleared_through_an_rc_back_reference: agora #482 — the container cleared inline through the Rc payload a field viewer of the element reaches, `( vec_clear ( rc_get u ) )`; the element read after
// Closed: another handle of the same Rc may be the same value, so the change ends the element (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop element read after its container is cleared through an rc back reference
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: E { ( Rc ( Vec E ) ) up String name }

@ main → i {
    : ( Rc ( Vec E ) ) r ( rc_new [( Vec E )] ( vec_new [E] ) )
    : ~ ( Vec E ) v ( rc_get [( Vec E )] r )
    ( vec_push [E] v @ E { ( rc_clone [( Vec E )] r ) ( string_from `an element name long enough for a heap buffer` ) } )
    ( vec_push [E] v @ E { ( rc_clone [( Vec E )] r ) ( string_from `a second element name long enough for a heap buffer` ) } )
    : ( Vec E ) cv ( rc_get [( Vec E )] r )
    ~ x cv {
        : ~ ( Rc ( Vec E ) ) u . x up
        ( vec_clear [E] ( rc_get [( Vec E )] u ) )
        ( nurl_println ( string_data . x name ) )
        break
    }
    ^ 0
}

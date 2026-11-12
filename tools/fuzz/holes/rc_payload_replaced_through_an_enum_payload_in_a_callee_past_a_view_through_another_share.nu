// rc_payload_replaced_through_an_enum_payload_in_a_callee_past_a_view_through_another_share: agora #734 — as rc_payload_replaced_through_an_option_payload_in_a_callee_past_a_view_through_another_share, an enum payload
// Closed: an Rc a callee hands to a replacer (`rc_set`) through a binding derived from its parameter — a `??` payload, a loop element, a slice element — is in its drop summary, which the same-Rc rule asks (__drop_note_via; agora #734, #735, #737).
// main 851e5cb3 (with the same-Rc reach, #712): accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #734: as rc_payload_replaced_through_an_option_payload_in_a_callee_past_a_view_through_another_share, an enum payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

: | E { A ( Rc ( Vec u ) ) B }

@ ch E e → v { ?? e { A h → { ( rc_set [( Vec u )] h ( vec_new [u] ) ) } B → {} } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : E e @ E { A r }
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch e )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

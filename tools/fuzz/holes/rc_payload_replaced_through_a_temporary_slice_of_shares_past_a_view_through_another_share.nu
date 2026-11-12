// rc_payload_replaced_through_a_temporary_slice_of_shares_past_a_view_through_another_share: agora #737 — `( ch ( slice_from_vec … hs ) )`, ch replacing `( slice_at hs 0 )`'s payload, beside a view through another share
// Closed: an Rc a callee hands to a replacer (`rc_set`) through a binding derived from its parameter — a `??` payload, a loop element, a slice element — is in its drop summary, which the same-Rc rule asks (__drop_note_via; agora #734, #735, #737).
// main 851e5cb3 (with the same-Rc reach, #712): accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #737: `( ch ( slice_from_vec … hs ) )`, ch replacing `( slice_at hs 0 )`'s payload, beside a view through another share
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ ch ( Slice ( Rc ( Vec u ) ) ) hs → v { : ( Rc ( Vec u ) ) h ( slice_at [( Rc ( Vec u ) )] hs 0 ) ( rc_set [( Vec u )] h ( vec_new [u] ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( ch ( slice_from_vec [( Rc ( Vec u ) )] hs ) )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

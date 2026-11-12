// payload_lent_through_a_chain_of_callees_out_of_a_vec_of_shares: `first_view` → `first_payload` → `first_share`, each handing back a lend of the next, its slice kept past `( wipe r )`
// Closed: a view's binding is marked with the Rc payloads its value is read through (`rcp_`: `rc_get` in its source expression, the bindings it names, a callee's answer g_fn_rcp); a call that may change one through another handle ends those views of a source that holds the Rc only in its elements' storage (agora #726).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #726: a payload lent through a chain of callees out of a Vec of shares, past a reset
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/deque.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

@ first_share ( Vec ( Rc ( Vec u ) ) ) hs → ( Rc ( Vec u ) ) { ^ ( vec_at [( Rc ( Vec u ) )] hs 0 ) }

@ first_payload ( Vec ( Rc ( Vec u ) ) ) hs → ( Vec u ) { ^ ( rc_get [( Vec u )] ( first_share hs ) ) }

@ first_view ( Vec ( Rc ( Vec u ) ) ) hs → ( Slice u ) { ^ ( slice_from_vec [u] ( first_payload hs ) ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs ( rc_clone [( Vec u )] r ) )
    : ( Slice u ) sl ( first_view hs )
    ( wipe r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

// trait_object_of_a_methodless_subtrait_holding_a_share_clears_the_payload: `% Tool [T] : Wiper { }`, a `%Tool` object holding a share whose Wiper method clears the payload, the caller viewing it through another handle
// Closed: a trait object reaches what the types implementing its trait — and its supertraits — reach (agora #738).
// main 160339c1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #738: a trait object of a methodless subtrait holding a share
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

% Wiper [T] {
    @ wipe_it T self → i
}

% Tool [T] : Wiper {}
: G { ( Rc ( Vec String ) ) r }

% Wiper G { @ wipe_it G g → i { ( vec_clear [String] ( rc_get [( Vec String )] . g r ) ) ^ 0 } }

% Tool G {}

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : %Tool d ( dyn Tool @ G { r } )
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( wipe_it d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

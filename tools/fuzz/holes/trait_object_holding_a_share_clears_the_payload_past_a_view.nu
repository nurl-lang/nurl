// trait_object_holding_a_share_clears_the_payload_past_a_view: `: %Wiper d ( dyn Wiper @ G { r } )` whose method clears `( rc_get . g r )`, the caller keeping a view through `r2`
// Closed: a trait object may box a value of any type implementing its trait, so it reaches the Rc types those reach (__rc_reach / __rc_direct of `%dyn.T`), and a `dyn` call drops what one of its impls drops (__dyn_virtual_drop_edges) — the same-Rc rule ends the view through another handle at the call (agora #738).
// main 160339c1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #738: a trait object holding a share clearing the payload past a view through another handle
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

% Wiper [T] {
    @ wipe_it T self → i
}

: G { ( Rc ( Vec String ) ) r }

% Wiper G { @ wipe_it G g → i { ( vec_clear [String] ( rc_get [( Vec String )] . g r ) ) ^ 0 } }

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : %Wiper d ( dyn Wiper @ G { r } )
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( wipe_it d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

// trait_object_holding_a_share_grows_the_payload_past_a_view: a trait object holding a share whose method grows the payload, the caller keeping a slice through another handle
// Closed: a trait object may box a value of any type implementing its trait, so it reaches the Rc types those reach (__rc_reach / __rc_direct of `%dyn.T`), and a `dyn` call drops what one of its impls drops (__dyn_virtual_drop_edges) — the same-Rc rule ends the view through another handle at the call (agora #738).
// main 160339c1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #738: a trait object holding a share growing the payload past a view through another handle
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

% Grower [T] {
    @ grow_it T self i n → i
}

: G { ( Rc ( Vec u ) ) r }

% Grower G { @ grow_it G g i n → i { ( vec_reserve [u] ( rc_get [( Vec u )] . g r ) n ) ^ 0 } }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : %Grower d ( dyn Grower @ G { r } )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    ( grow_it d 4096 )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

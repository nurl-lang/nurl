// trait_object_with_an_unsafe_impl_beside_a_safe_one_stays_refused: a trait whose method has an `unsafe` impl beside a safe one: the dyn call keeps the mutation summary of the raw one
// Kept: a dyn call whose impls are not all safe code is answered by the mutation summary, as before — its drop summary would miss the raw impl's change (agora #738's review).
// main 160339c1: refused.
// map: §2.10 | A2 | rejected | - | agora #738: a dyn call over an unsafe impl beside a safe one
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

% Wiper [T] {
    @ wipe_it T self ( Rc ( Vec String ) ) x → i
}

: G { i k }
: H { i k }

% Wiper G { @ wipe_it G g ( Rc ( Vec String ) ) x → i { ^ . g k } }

% Wiper H { unsafe @ wipe_it H h ( Rc ( Vec String ) ) x → i { ( vec_clear [String] ( rc_get [( Vec String )] x ) ) ^ 0 } }

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : %Wiper d ( dyn Wiper @ H { 1 } )
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( wipe_it d r )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

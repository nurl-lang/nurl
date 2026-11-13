// vec_of_trait_objects_holding_shares_cleared_runs_clean: `( vec_clear plugins )` of a `( Vec %Plugin )` whose impls hold shares and have no `% Drop`, beside a view through another handle
// Kept: dropping a trait object runs the program's own code only where an implementing type has a % Drop; a library dropper of a Vec of them is still the library's (agora #738's review).
// main 160339c1: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #738: clearing a Vec of trait objects holding shares, no Drop
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

% Plugin [T] {
    @ score T self i x → i
}

: Counter { ( Rc ( Vec String ) ) names }
: Fixed { i k }

% Plugin Counter { @ score Counter c i x → i { ^ + x ( vec_len [String] ( rc_get [( Vec String )] . c names ) ) } }

% Plugin Fixed { @ score Fixed f i x → i { ^ + x . f k } }

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : ( Vec % Plugin ) ps ( vec_new [% Plugin] )
    ( vec_push [% Plugin] ps ( dyn Plugin @ Counter { ( rc_clone [( Vec String )] r ) } ) )
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( vec_clear [% Plugin] ps )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

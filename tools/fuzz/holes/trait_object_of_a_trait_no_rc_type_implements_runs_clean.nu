// trait_object_of_a_trait_no_rc_type_implements_runs_clean: a `dyn Wiper` of a type holding no Rc, with no Rc-holding impl of the trait, cleared beside a view through a share
// Kept: a trait object whose trait no Rc-holding type implements reaches no Rc — a view through a share stays valid across its dyn call (agora #738).
// main 160339c1: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #738: a trait object whose trait no Rc-holding type implements
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

% Wiper [T] {
    @ wipe_it T self → i
}

: N { ( Vec String ) v }

% Wiper N { @ wipe_it N n → i { ( vec_clear [String] . n v ) ^ 0 } }

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : %Wiper d ( dyn Wiper @ N { ( vec_new [String] ) } )
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( wipe_it d )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

// loop_element_of_a_param_handed_to_a_reading_fn_runs_clean: as loop_element_of_a_param_handed_to_a_clearing_fn, with the callee only reading the payload of w's share
// AGORA-811 guard: accepted - reading drops nothing
// map: §2.10 | A2 | runs-clean | - | AGORA-811
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: G { ( Rc ( Vec String ) ) r }

@ wipe G g → v { ( nurl_println_int ( vec_len [String] ( rc_get [( Vec String )] . g r ) ) ) }

@ each ( Vec G ) ws → v { ~ w ws { ( wipe w ) } }

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : ( Vec G ) ws ( vec_new [G] )
    ( vec_push [G] ws @ G { r } )
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( each ws )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

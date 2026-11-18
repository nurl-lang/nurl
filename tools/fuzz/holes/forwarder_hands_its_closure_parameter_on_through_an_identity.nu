// forwarder_hands_its_closure_parameter_on_through_an_identity: a forwarder `^ ( idc f )` handed a builder's closure, run beside a view of xs
// Closed (agora #813): a callee that hands back the closure it was handed (`retclo`) hands back its effects too (`__ce_by_arg`), and a call of a builder whose answer is not there yet gives placeholders resolved at the walk; the result's run replays them.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (155).
// map: §2.10 | A2 | rejected | - | agora #838: a forwarder `^ ( idc f )` handed a builder's closure, run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ idc ( @ v ) f → ( @ v ) { ^ f }

@ fw ( @ v ) f → ( @ v ) { ^ ( idc f ) }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( fw ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

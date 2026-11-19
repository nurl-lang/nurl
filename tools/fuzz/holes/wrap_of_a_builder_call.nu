// wrap_of_a_builder_call: `( wrap ( mk xs ) )`, wrap returning `\ → v { ( f ) }` over its parameter, run beside a view
// Closed (agora #813): a callee that hands back the closure it was handed (`retclo`) hands back its effects too (`__ce_by_arg`), and a call of a builder whose answer is not there yet gives placeholders resolved at the walk; the result's run replays them.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (167).
// map: §2.10 | A2 | rejected | - | agora #838: `( wrap ( mk xs ) )`, wrap returning `\ → v { ( f ) }` over its parameter, run beside a view
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ wrap ( @ v ) f → ( @ v ) { ^ \ → v { ( f ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( wrap ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

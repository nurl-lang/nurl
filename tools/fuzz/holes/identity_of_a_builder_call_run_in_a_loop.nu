// identity_of_a_builder_call_run_in_a_loop: `( idc ( mk xs ) )` run in a loop beside a view of xs
// Closed (agora #813): a callee that hands back the closure it was handed (`retclo`) hands back its effects too (`__ce_by_arg`), and a call of a builder whose answer is not there yet gives placeholders resolved at the walk; the result's run replays them.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (102).
// map: §2.10 | A2 | rejected | - | agora #838: `( idc ( mk xs ) )` run in a loop beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ idc ( @ v ) f → ( @ v ) { ^ f }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ( @ v ) c ( idc ( mk xs ) )
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    : ~ i k 0
    ~ < k 2 { ( c ) = k + k 1 }
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

// identity_inside_a_loop_then_run: a builder call handed through an identity inside a loop, run beside a view of xs
// Closed (agora #813): a callee that hands back the closure it was handed (`retclo`) hands back its effects too (`__ce_by_arg`), and a call of a builder whose answer is not there yet gives placeholders resolved at the walk; the result's run replays them.
// main e35ded15: accepted; the read after the run prints a freed buffer's bytes (192).
// map: §2.10 | A2 | rejected | - | agora #838: a builder call handed through an identity inside a loop, run beside a view of xs
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ idc ( @ v ) f → ( @ v ) { ^ f }

@ mk ( Vec u ) x → ( @ v ) { ^ \ → v { ( vec_reserve [u] x 4096 ) } }

@ main → i {
    : ( Vec u ) xs ( vec_new [u] )
    ( vec_push [u] xs 7 )
    : ~ ( @ v ) c \ → v {}
    : ~ i k 0
    ~ < k 2 { = c ( idc ( mk xs ) ) = k + k 1 }
    : ( Slice u ) sl ( slice_from_vec [u] xs )
    ( c )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

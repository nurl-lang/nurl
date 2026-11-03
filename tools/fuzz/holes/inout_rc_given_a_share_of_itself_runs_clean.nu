// inout_rc_given_a_share_of_itself_runs_clean: agora #456 guard — an `inout ( Rc String )` given another share of its own control block
// Guard: a share of the same Rc has the same key — the same state: kept, no extra share, nothing released.
// main: runs clean.
// map: §7.6 | A2 | runs-clean | - | agora #456 guard: an inout Rc given a share of itself
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

@ idr ( Rc String ) r → ( Rc String ) { ^ r }

@ put inout ( Rc String ) o ( Rc String ) other → v { = o ( idr other ) }

@ main → i {
    : ~ ( Rc String ) a ( rc_new [String] ( string_from `a fresh string long enough for the heap, one` ) )
    : ( Rc String ) x ( rc_clone [String] a )
    ( put a x )
    ( nurl_println ( string_data ( rc_get [String] a ) ) )
    ( nurl_println ( string_data ( rc_get [String] x ) ) )
    ^ 0
}

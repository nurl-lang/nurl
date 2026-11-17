// slice_join_of_lending_call_arms_runs_clean: `: [i x ? c ( first a ) a`, `( ln ? c ( pick a k ) a )`: a call arm that lends its argument back is no owner on those runs, and `a` is released once
// Twin of agora #893: the call arm counts by its answer, which is "not the caller's" where it lends `a` back: no double release of `a`, and `pick`'s fresh literal is released on its runs.
// map: §7.6 | A2 | runs-clean | - | AGORA-893 twin: a join of a lending call arm and its argument releases the argument once
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ first [i a → [i { ^ a }
@ pick [i a b k → [i { ? k { ^ a } { ^ [i | 4 5] } }
@ ln [i a → i { ^ . a 1 }
@ run b c b k → v { : [i a [i | 1 2] : [i x ? c ( first a ) a ( nurl_println_int ( ln x ) ) ( nurl_println_int ( ln ? c ( first a ) a ) ) : [i y ? c ( pick a k ) a ( nurl_println_int ( ln y ) ) ( nurl_println_int ( ln ? c ( pick a k ) a ) ) ( nurl_println_int ( ln a ) ) }
@ main → i { ( run T T ) ( run T F ) ( run F T ) ( run F F ) ^ 0 }

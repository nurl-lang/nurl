// vec_of_shares_freed_by_a_sink_helper_past_a_view_through_a_clone_runs_clean: `@ discard sink ( Vec ( Rc ( Vec u ) ) ) hs → v { ( vec_free hs ) }` handed a Vec holding `r`, while a slice of the payload is taken through `r2`: a library dropper handed it whole drops handles (the shape the fix must keep)
// Closed: a binding handed to a `sink` parameter, or a value no binding names, is swept as a call handed another handle: what the callee's summaries drop, replace or move of an Rc's payload through it ends the views another handle took — and a sink argument or a clone of a parameter forwarded on is in the function's own drop summary (agora #733).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #733: a Vec of shares freed by a sink helper, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`

@ discard sink ( Vec ( Rc ( Vec u ) ) ) hs → v { ( vec_free [( Rc ( Vec u ) )] hs ) }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ( Rc ( Vec u ) ) r2 ( rc_clone [( Vec u )] r )
    : ( Slice u ) sl ( slice_from_vec [u] ( rc_get [( Vec u )] r2 ) )
    : ~ ( Vec ( Rc ( Vec u ) ) ) hs ( vec_new [( Rc ( Vec u ) )] )
    ( vec_push [( Rc ( Vec u ) )] hs r )
    ( discard hs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}

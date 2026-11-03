// view_kept_in_an_inout_by_a_callee_changing_a_lent_first_argument_leaves_that_one_alone: agora #414 — `( put2m ? == c 1 vs vs2 out ( string_data loc ) )`, `put2m` pushing a literal into its first argument and the view into its `inout` second; `vs` read after the block (the shape the fix must keep)
// Closed: a callee that changes a first argument that is a value lent out of a binding (`@sx`) keeps a view there only where its own walk says it may (g_fn_vholds: the holders of the values it keeps); the `inout` argument it keeps the view in holds it (bck_vpass_own; agora #414).
// main: runs clean.
// map: PushArg | A1 | runs-clean | - | agora #414: a view kept in an inout argument by a callee that changes a lent first argument too, the first one read after its source ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ put2m ( Vec s ) a inout ( Vec s ) b s x → v { ( vec_push [s] a `lit` ) ( vec_push [s] b x ) }

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    : ( Vec s ) vs2 ( vec_new [s] )
    : ~ ( Vec s ) out ( vec_new [s] )
    : i c 1
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        ( put2m ? == c 1 vs vs2 out ( string_data loc ) )
        ( nurl_println ( vec_at [s] out 0 ) )
    }
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}

// arm_slice_local_or_block_argument_tail_releases_the_arm_locals_runs_clean: a `?` arm with a slice literal local whose tail lends out of an outer Vec (also in a loop), and an arm whose tail call is handed a value block over a block local; both paths.
// Closed (agora #830): an arm's slices are parked with its other locals and freed on the runs those go (mem_arm_exit_open's `__x_slices`, __slice_free_when); a value block's tail binding is published with the call (`__last_call_join_phi__`) and taken for the arm's own (mem_arm_take_call).
// main 4403a920: the slice buffer, and the block's String, leak on each run (definitely lost).
// map: §7.6 | A2 | runs-clean | - | agora #830: an arm's slice local and a block argument's local are released
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i k → String { ^ ( string_from ( nurl_str_cat ( nurl_str_int k ) ` a heap string long enough` ) ) }

@ idg [T] T x → T { ^ x }

@ mkv → ( Vec String ) { : ~ ( Vec String ) v ( vec_new [String] ) ( vec_push [String] v ( mk 0 ) ) ^ v }

@ slice_arm i c → v { : ( Vec String ) v ( mkv ) : String e ? == c 1 { : [i sl [i | 1 2 3] ( vec_at [String] v 0 ) } ( mk 3 ) ( nurl_println ( string_data e ) ) }
@ slice_arm_loop i c → v {
    : ( Vec String ) v ( mkv )
    : ~ i k 0
    ~ < k 3 {
        : String e ? == c 1 { : [i sl [i | 1 2 3] ( vec_at [String] v 0 ) } ( mk 3 )
        ( nurl_println ( string_data e ) )
        = k + k 1
    }
}
@ block_arg i c → v { : String e ? == c 1 ( idg [String] { : String t ( mk 3 ) t } ) ( mk 3 ) ( nurl_println ( string_data e ) ) }
@ main → i { ( slice_arm 0 ) ( slice_arm 1 ) ( slice_arm_loop 0 ) ( slice_arm_loop 1 ) ( block_arg 0 ) ( block_arg 1 ) ^ 0 }

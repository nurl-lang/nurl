// map: §7.6 | A2 | runs-clean | - | AGORA-953 (agora #242 twin): `: g { : i z ( a 1 ) a }  = a g`: g is a second name of a's env, so `=` releases nothing where the new env is the old one
// twin of tools/fuzz/holes/closure_assigned_a_value_block_ending_in_itself_runs_clean.nu (tools/fuzz/holes/elab.py)
$ `stdlib/core/string.nu`

@ mkn i n → ( @ i i ) { ^ \ i x → i { ^ + x n } }

@ main → i {
    : String tag ( string_from `tag string long enough for a heap buffer` )
    : ~ ( @ i i ) a \ i x → i { ^ + x ( string_len tag ) }
    : __el { : i z ( a 1 ) a }
    = a __el
    ( nurl_println_int ( a 1 ) )
    ^ 0
}

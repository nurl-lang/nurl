// map: §7.6 | A2 | rejected | - | agora #242: elaborated twin: `: g { : i z ( a 1 ) a }  = a g`, a closure bound from a value block whose tail is the target closure
// AGORA-869: heap-use-after-free under ASan with the walk alone; the ownership engine refuses it (codegen makes no copy here, unlike the unbound spelling).
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

// inout_parameter_join_of_value_blocks_handed_to_a_sink_runs_clean: agora #555 guard — `( eat ? == c 1 { p } { p } )`, p an `inout` parameter.
// Guard: as inout_parameter_value_block_handed_to_a_sink_runs_clean, through a join of blocks.
// main: runs clean.
// map: §2.12 | A2 | runs-clean | - | agora #555 guard: a join of value blocks of an inout parameter handed to a sink
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }
: H { ( Vec S ) a ( Vec S ) b }
: G { H x i k }

@ eat sink ( Vec S ) v → i { ^ # i ( vec_len [S] v ) }

@ mkv i k → ( Vec S ) {
    : ( Vec S ) va ( vec_new [S] )
    ( vec_push [S] va @ S { ( string_from `an element string long enough for a heap buffer` ) k } )
    ^ va
}

@ mkh → H { ^ @ H { ( mkv 1 ) ( mkv 2 ) } }

@ f inout ( Vec S ) p i c → i { ^ ( eat ? == c 1 { p } { p } ) }

@ main → i {
    : ~ ( Vec S ) w ( mkv 1 )
    ( nurl_println_int ( f w 1 ) )
    ^ 0
}

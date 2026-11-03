// view_param_copied_into_an_inout_holder_source_outlives_runs_clean: the holder read while the viewed String lives.
// The shape the fix must keep.
// main 4d57d596: runs clean.
// map: §2.7 | A2 | runs-clean | - | agora #346: the holder read while the viewed String lives
$ `stdlib/core/string.nu`

: V { s v }

@ setw inout V w s p → v {
    : s t p
    = w @ V { t }
}

@ main → i {
    : String b ( string_from `a heap string long enough to be on the heap for sure` )
    : ~ V w @ V { `literal` }
    ( setw w ( string_data b ) )
    ( nurl_println . w v )
    ^ 0
}

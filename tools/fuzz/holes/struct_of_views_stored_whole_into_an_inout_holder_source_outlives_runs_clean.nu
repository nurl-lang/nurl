// struct_of_views_stored_whole_into_an_inout_holder_source_outlives_runs_clean: the holder read while the viewed String lives.
// The shape the fix must keep.
// main 4d57d596: runs clean.
// map: §2.7 | A2 | runs-clean | - | agora #380: the holder read while the viewed String lives
$ `stdlib/core/string.nu`

: W { s v }

@ put inout W w W x → v { = w x }

@ main → i {
    : String b ( string_from `a string that outlives the holder` )
    : ~ W w @ W { `a literal` }
    ( put w @ W { ( string_data b ) } )
    ( nurl_println . w v )
    ^ 0
}

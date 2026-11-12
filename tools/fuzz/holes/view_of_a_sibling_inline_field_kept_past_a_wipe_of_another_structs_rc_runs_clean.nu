// view_of_a_sibling_inline_field_kept_past_a_wipe_of_another_structs_rc_runs_clean: a view of `. ctx name` kept past clearing the shared Rc payload of another `Ctx`: the String is the struct's own, no Rc's payload (the shape the fix must keep)
// Closed: the rule compares what a call may change through an argument with what a view's source is or holds in its own storage (agora #712).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #712: a view of an inline field kept past a wipe of another struct's Rc
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

: Ctx { ( Rc ( Vec String ) ) log String name }

@ wipe Ctx c → v { ( vec_clear [String] ( rc_get [( Vec String )] . c log ) ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v )
    : Ctx ctx @ Ctx { ( rc_clone [( Vec String )] r ) ( string_from `a name long enough to live on the heap` ) }
    : Ctx other @ Ctx { r ( string_from `another name long enough to live on the heap` ) }
    : ( Slice u ) nm ( string_bytes . ctx name )
    ( wipe other )
    ( nurl_println_int # i ( slice_at [u] nm 0 ) )
    ^ 0
}

// string_param_sunk_into_a_vec_after_its_view_was_kept: agora #337 — a callee leaves its `inout` holder viewing a `sink` String's buffer, then pushes the String into an `inout` Vec the caller drops before the holder is read (#337 item 5).
// Closed: the callee's pairs tie the holder to the Vec the String went into (g_fn_vkeeps, agora #337).
// main: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #337: a sink String viewed into a holder, then moved into another argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ f inout W w sink String src inout ( Vec String ) out → v {
    = w @ W { ( string_data src ) }
    ( vec_push [String] out src )
}

@ main → i {
    : ~ W w @ W { `literal` }
    {
        : ~ ( Vec String ) out ( vec_new [String] )
        ( f w ( string_from `a string moved into out, freed with it` ) out )
    }
    ( nurl_println . w v )
    ^ 0
}

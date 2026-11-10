// inout_view_param_stored_into_an_s_global: agora #466 — `@ note inout s x → v { = g_err x }`: a global given a view of what the caller passed
// main c4d36651: accepted; the global outlived the String it viewed.
// map: §2.10 | A2 | rejected | - | agora #466: `@ note inout s x → v { = g_err x }`: a global given a view of what the caller passed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: ~ s g_err ``

@ note inout s x → v { = g_err x }

@ main → i {
    {
        : String m ( string_from `a heap string long enough to be on the heap for sure` )
        : ~ s x ( string_data m )
        ( note x )
    }
    ( nurl_println g_err )
    ^ 0
}

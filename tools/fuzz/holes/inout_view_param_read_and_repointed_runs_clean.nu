// inout_view_param_read_and_repointed_runs_clean: agora #466 — an inout view parameter only read, and an inout struct of views re-pointed at a literal
// Control for agora #466.
// map: §2.10 | A2 | runs-clean | - | agora #466: an inout view parameter only read, and an inout struct of views re-pointed at a literal
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }

@ look inout s x → i { ^ ( nurl_str_len x ) }

@ repoint inout W w → v { = w @ W { `a literal` } }

@ main → i {
    : String m ( string_from `a heap string long enough to be on the heap for sure` )
    : ~ s x ( string_data m )
    ( nurl_println_int ( look x ) )
    : ~ W w @ W { ( string_data m ) }
    ( repoint w )
    ( nurl_println . w v )
    ^ 0
}

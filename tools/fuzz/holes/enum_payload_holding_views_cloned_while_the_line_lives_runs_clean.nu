// enum_payload_holding_views_cloned_while_the_line_lives_runs_clean: a Vec-of-views payload cloned out, the String it views still alive.
// The shape the fix must keep: a payload that holds views depends on what its enum views, so a copy of it lives as long as that.
// main 24e95a81: runs clean.
// map: §2.13 | A2 | runs-clean | - | agora #338: a Vec-of-views payload cloned out, the String it views still alive
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Pkt { Toks ( Vec s ) NoToks String }

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ~ ( Vec s ) keep ( vec_new [s] )
    {
        : ( Vec s ) v ( vec_new [s] )
        ( vec_push [s] v ( string_data line ) )
        : Pkt p @ Pkt { Toks v }
        ?? p { Toks xs → { = keep ( vec_clone [s] xs ) } NoToks e → {} }
    }
    ( nurl_println ( vec_at [s] keep 0 ) )
    ^ 0
}

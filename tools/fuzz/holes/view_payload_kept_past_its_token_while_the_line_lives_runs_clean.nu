// view_payload_kept_past_its_token_while_the_line_lives_runs_clean: a view payload kept past its token, the String it views still alive.
// The shape the fix must keep: a view payload points where the token views, not into the token, so it may outlive the token (`__vpay_srcs`).
// main 24e95a81: runs clean.
// map: §2.13 | A2 | runs-clean | - | agora #338: a view payload kept past its token, the String it views still alive
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ( Vec s ) outs ( vec_new [s] )
    {
        : Tok t @ Tok { Word ( string_data line ) }
        ?? t { Word w → { ( vec_push [s] outs w ) } Num n → {} Bad b → {} }
    }
    ( nurl_println ( vec_at [s] outs 0 ) )
    ^ 0
}

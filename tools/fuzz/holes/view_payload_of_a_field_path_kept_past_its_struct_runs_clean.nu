// view_payload_of_a_field_path_kept_past_its_struct_runs_clean: a view payload of `?? . h t` kept past h, the String it views still alive.
// The shape the fix must keep: a view payload of a struct field matched in place is lent from what the struct views (`__vpay_srcs`).
// main 24e95a81: runs clean.
// map: §2.13 | A2 | runs-clean | - | agora #338: a view payload of `?? . h t` kept past h, the String it views still alive
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | Tok { Word s Num i Bad String }

: H { Tok t String own }

@ main → i {
    : String line ( string_from `hello world, long enough for a heap buffer` )
    : ( Vec s ) outs ( vec_new [s] )
    {
        : H h @ H { @ Tok { Word ( string_data line ) } ( string_from `own` ) }
        ?? . h t { Word w → { ( vec_push [s] outs w ) } Num n → {} Bad b → {} }
    }
    ( nurl_println ( vec_at [s] outs 0 ) )
    ^ 0
}

// both_payload_bindings_of_an_enum_read_runs_clean: agora #460 — both payload bindings of one enum only read, an element borrow living across the inner match
// Control for agora #460.
// map: §2.10 | A2 | runs-clean | - | agora #460: both payload bindings of one enum only read, an element borrow living across the inner match
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E { Some ( Vec String ) None }

@ main → i {
    : ( Vec String ) inner ( vec_new [String] )
    ( vec_push [String] inner ( string_from `an element string long enough for a heap buffer` ) )
    : E e @ E { Some inner }
    ?? e { Some xs → {
            : String s0 ( vec_at [String] xs 0 )
            ?? e { Some ys → { ( nurl_println_int ( vec_len [String] ys ) ) } None → {} }
            ( nurl_println_int ( string_len s0 ) )
        } None → {} }
    ^ 0
}

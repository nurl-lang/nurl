// enum_payload_element_read_before_a_clearer_of_the_enum_runs_clean: agora #424 — the element read before the clear, and the payload itself after it: the payload stays, empty
// Control for agora #424 / #569.
// map: §2.10 | A2 | runs-clean | - | agora #424: the element read before the clear, and the payload itself after it: the payload stays, empty
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: | Bag { Nobag Fullbag ( Vec String ) }

@ clr Bag b → v { ?? b { Fullbag xs → { ( vec_clear [String] xs ) } Nobag → {} } }

@ main → i {
    : ( Vec String ) inner0 ( vec_new [String] )
    ( vec_push [String] inner0 ( string_from `an element string long enough for a heap buffer` ) )
    : Bag o @ Bag { Fullbag inner0 }
    ?? o { Fullbag inner → {
            : String s0 ( vec_at [String] inner 0 )
            ( nurl_println_int ( string_len s0 ) )
            ( clr o )
            ( nurl_println_int ( vec_len [String] inner ) )
        } Nobag → {} }
    ^ 0
}

// share_handed_to_a_sink_helper_that_grows_an_element_of_its_payload: a sink helper growing a String element of `( rc_get h )` while `string_data` of that element is taken through `r2`
// Closed: a binding handed to a `sink` parameter, or a value no binding names, is swept as a call handed another handle: what the callee's summaries drop, replace or move of an Rc's payload through it ends the views another handle took — and a sink argument or a clone of a parameter forwarded on is in the function's own drop summary (agora #733).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #733: a sink helper growing an element of a share's payload, past a view through a clone
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ grow ( Rc ( Vec String ) ) h → v { : ~ i k 0 ~ < k 200 { ( string_push_str ( vec_at [String] ( rc_get [( Vec String )] h ) 0 ) `more and more text to move the buffer ` ) = k + k 1 } }

@ growb ( Vec String ) p → v { : ~ i k 0 ~ < k 200 { ( string_push_str ( vec_at [String] p 0 ) `more and more text to move the buffer ` ) = k + k 1 } }

@ ch sink ( Rc ( Vec String ) ) h → v { ( grow h ) }

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : s e ( string_data ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( ch r )
    ( nurl_println e )
    ^ 0
}

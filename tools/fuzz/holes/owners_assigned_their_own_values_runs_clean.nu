// owners_assigned_their_own_values_runs_clean: agora #554 guard — an owned Vec and an owned String each given its own value (`= v v`, `= s s`), then grown, read and handed to a `sink`.
// Guard: a self-assignment changes nothing: the owners stay owners.
// main: runs clean.
// map: §2.1 | A1 | runs-clean | - | agora #554 guard: owners given their own values, grown and handed over
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat sink ( Vec String ) v → i { ^ # i ( vec_len [String] v ) }

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    = v v
    ( vec_push [String] v ( string_from `two` ) )
    : ~ String s ( string_from `abc` )
    = s s
    ( string_push_str s `def` )
    ( nurl_println ( string_data s ) )
    ( nurl_println_int ( eat v ) )
    ^ 0
}

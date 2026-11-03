// result_lend_handed_to_a_library_keeper: agora #459 — `( res_unwrap_or [String E] ( maybr o k ) … )`, stdlib's generic `res_unwrap_or` taking its result over, handed a call's result that is `o`'s own value on one run
// Closed: a library function compiled after its caller answers whether it takes the argument over at module end (consume_flag): the lend is copied on the runs it lends (agora #459).
// main: heap-use-after-free (base 8a2afbc3).
// map: §7.6 | A2 | runs-clean | - | agora #459: a lend handed to stdlib's res_unwrap_or
$ `stdlib/core/string.nu`
$ `stdlib/core/result.nu`

: | E { Bad }

@ mkr s t → !String E { ^ @ !String E { T ( string_from t ) } }

@ maybr ! String E a i k → !String E { ? == k 0 { ^ a } {} ^ ( mkr `a fresh result long enough for the heap here` ) }

@ shr ! String E o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F _ → { ( nurl_println `bad` ) } } }

@ run i k → v {
    : !String E o ( mkr `the owner long enough for the heap here` )
    : String s ( res_unwrap_or [String E] ( maybr o k ) ( string_from `a default long enough for the heap here` ) )
    ( nurl_println ( string_data s ) )
    ( shr o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}

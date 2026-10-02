// cond_param_return.nu — a function that hands back its borrowed parameter
// on one path and a fresh value on another answers per call.
//
// `@ cap String src → String { ? short { ^ src } {} ^ ( string_substr … ) }`
// was summarised as a lender throughout: a caller binding its result never
// dropped the fresh one (a leak), and a caller returning it over its own
// local (`^ ( cap body )`) dropped `body` under the result it lent — a
// use-after-free (examples/claude_agent's truncate_for_model). Now the
// paths' answer is published per call, and a lent result returned past the
// local it lends from is copied.

$ `stdlib/core/string.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

@ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ cap String src → String {
    ? <= ( string_len src ) 8 { ^ src } {}
    ^ ( string_substr src 0 8 )
}

@ make s text → String {
    : String body ( string_from text )
    ^ ( cap body )
}

@ main → i {
    : i l0 ( live )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 10 {
        : String a ( make `short` )
        : String b ( make `a much longer text` )
        : String src ( string_from ? == % k 2 0 `tiny` `another longer one` )
        : String c ( cap src )
        = acc + + + acc ( string_len a ) ( string_len b ) ( string_len c )
        = k + k 1
    }
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ( nurl_print `live: ` ) ( nurl_print_int - ( live ) l0 ) ( nurl_print `\n` )
    ^ 0
}

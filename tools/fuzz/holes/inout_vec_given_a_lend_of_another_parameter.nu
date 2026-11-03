// inout_vec_given_a_lend_of_another_parameter: agora #438 — `@ vput inout ( Vec i ) o ( Vec i ) other → v { = o ( vid other ) }`
// Closed: an `inout` String or Vec given a call's lend is compared with its old value by key at run time: the old value itself stays; anything else is copied in where the call lent it, and the old value goes (agora #438).
// main: heap-use-after-free (base 22fd0184 too).
// map: §7.6 | A2 | runs-clean | - | agora #438: `@ vput inout ( Vec i ) o ( Vec i ) other → v { = o ( vid other ) }`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

@ vid ( Vec i ) v → ( Vec i ) { ^ v }

@ vput inout ( Vec i ) o ( Vec i ) other → v { = o ( vid other ) }

@ main → i {
    : ~ ( Vec i ) a ( vec_new [i] )
    ( vec_push [i] a 1 )
    : ( Vec i ) x ( vec_new [i] )
    ( vec_push [i] x 2 )
    ( vput a x )
    ( nurl_println ( nurl_str_int ( vec_at [i] a 0 ) ) )
    ( nurl_println ( nurl_str_int ( vec_at [i] x 0 ) ) )
    ^ 0
}

// inout_option_given_a_call_that_may_lend_another_parameter: agora #343 — `= out ( maybe a k )`, out an inout ?String, maybe handing back its argument on some runs
// Closed: an `inout` option of an owned value given a call's lend is compared with its old value by its payload's key at run time: the old value itself stays; a lend of anything else is copied in and the old value released in place (agora #343).
// main: heap-use-after-free (base 145095d9 too).
// map: §7.6 | A2 | runs-clean | - | agora #343: `= out ( maybe a k )`, out an inout ?String, maybe handing back its argument on some runs
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: H { ? String o i n }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ sho ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ set inout ? String out ? String a i k → v { = out ( maybe a k ) }

@ run i k → v {
    : ~ ? String dst ( mk `the destination value long enough for heap` )
    : ~ ? String o ( mk `the owner value long enough for the heap` )
    ( set dst o k )
    = o ( mk `a replacement owner long enough for the heap` )
    ( sho dst )
    ( sho o )
}

@ main → i {
    ( run 0 )
    ^ 0
}

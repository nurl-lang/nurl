// option_owner_given_back_its_value_on_some_runs_by_a_call: agora #388 — `= o ( maybe o k )`, maybe handing back its argument when k is 0 and a fresh value otherwise, defined above its caller
// Closed: a function handing back its option parameter as is (`^ a`) answers "lent" per call, as for a String or Vec parameter, so the caller keeps its old value on the run that hands it back (gen_ret; agora #388).
// main: heap-use-after-free (base acf4f905 too).
// map: §7.6 | A2 | runs-clean | - | agora #388: `= o ( maybe o k )`, maybe handing back its argument when k is 0 and a fresh value otherwise, defined above its caller
$ `stdlib/core/string.nu`

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ maybe ? String a i k → ?String { ? == k 0 { ^ a } {} ^ ( mk `a fresh value long enough for the heap here` ) }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ run i k → v {
    : ~ ? String o ( mk `the owner's value, long enough for the heap` )
    = o ( maybe o k )
    ( show o )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}

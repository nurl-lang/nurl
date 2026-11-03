// inout_option_given_a_lend_of_another_parameter: agora #343 — `@ put inout ?String o ?String other → v { = o ( idopt other ) }`
// Closed: an `inout` option of an owned value given a call's lend is compared with its old value by its payload's key at run time: the old value itself stays; a lend of anything else is copied in and the old value released in place (agora #343).
// main: heap-use-after-free (base 145095d9 too).
// map: §7.6 | A2 | runs-clean | - | agora #343: `@ put inout ?String o ?String other → v { = o ( idopt other ) }`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ make → String { ^ ( string_from `a fresh string long enough for the heap, one` ) }

@ make2 → String { ^ ( string_from `a fresh string long enough for the heap, two` ) }

@ id String a → String { ^ a }

@ pick String a String b i k → String { ? == k 0 { ^ a } {} ^ b }

@ idopt ? String a → ?String { ^ a }

@ put inout ? String o ? String other → v { = o ( idopt other ) }

@ main → i {
    : ~ ? String a @ ?String { T ( make ) }
    : ?String x @ ?String { T ( make2 ) }
    ( put a x )
    ?? a { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } }
    ?? x { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } }
    ^ 0
}

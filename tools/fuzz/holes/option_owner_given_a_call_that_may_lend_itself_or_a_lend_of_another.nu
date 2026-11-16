// option_owner_given_a_call_that_may_lend_itself_or_a_lend_of_another: agora #412 — `= o ( pick o ( id other ) k )`: the other argument the callee may lend is a call that lends `other`, no bare name
// Closed: every argument the callee may lend counts, by position: one that is no bare name but may lend what it reads — a call that lends, a field, a join — is another (__lend_pos_unnamed, agora #412).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #412: `= o ( pick o ( id other ) k )`: the other argument the callee may lend is a call that lends `other`, no bare name
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ id ? String a → ?String { ^ a }

@ run i k → v {
    : ?String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    = o ( pick o ( id other ) k )
    ( show o )
    ( show other )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}

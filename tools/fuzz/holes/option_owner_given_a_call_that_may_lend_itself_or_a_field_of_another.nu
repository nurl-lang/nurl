// option_owner_given_a_call_that_may_lend_itself_or_a_field_of_another: agora #412 — `= o ( pick o . s y k )`: the other argument the callee may lend is a field of a struct
// Closed: every argument the callee may lend counts, by position: a field is another (__lend_pos_unnamed, agora #412).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #412: `= o ( pick o . s y k )`: the other argument the callee may lend is a field of a struct
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

: S { ? String x ? String y }

@ run i k → v {
    : ?String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    : S s @ S { ( mk `a field value long enough for the heap` ) ( mk `a y value long enough for the heap here` ) }
    = o ( pick o . s y k )
    ( show . s y )
    ( show o )
    ( show other )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
